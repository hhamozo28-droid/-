import { OtpPurpose } from '@prisma/client';
import { prisma } from '../../config/prisma';
import { env } from '../../config/env';
import { normalizeAndHashAlgerianPhone } from '../../common/crypto/algeria-phone';
import {
  generateSixDigitOtp,
  hashOtpCode,
  sha256Hex,
  signAccessToken,
  signRefreshToken,
  verifyOtpHashConstantTime,
  verifyRefreshToken,
} from '../../common/crypto/security';
import { AppError } from '../../common/errors/app-error';
import { ISmsProvider, smsProvider } from '../../providers/sms.provider';
import {
  ConfirmChangePhoneInput,
  RefreshTokenInput,
  RequestChangePhoneInput,
  SendOtpInput,
  VerifyOtpInput,
} from './auth.schemas';

export interface AuthTokensResponse {
  accessToken: string;
  refreshToken: string;
  expiresInSeconds: number;
  user: {
    id: string;
    phoneMasked: string;
    preferredLang: string;
    createdAt: string;
  };
}

export class AuthService {
  constructor(private readonly sms: ISmsProvider = smsProvider) {}

  /**
   * Step 1: Validate Algerian mobile phone (+213), enforce anti-pumping cooldown,
   * store ONLY HMAC hashes in DB, and dispatch 6-digit SMS OTP.
   */
  public async sendLoginOtp(
    input: SendOtpInput,
    requestIp: string,
  ): Promise<{
    phoneMasked: string;
    expiresInSeconds: number;
    resendCooldownSeconds: number;
  }> {
    const normalized = normalizeAndHashAlgerianPhone(input.phone);

    await this.enforceOtpCooldown(normalized.phoneHash, OtpPurpose.LOGIN);

    const otpCode = generateSixDigitOtp();
    const otpHash = hashOtpCode(normalized.phoneHash, otpCode);
    const expiresAt = new Date(Date.now() + env.OTP_EXPIRY_MINUTES * 60 * 1000);

    // Invalidate any previous unconsumed login OTPs for this phone hash
    await prisma.otpChallenge.updateMany({
      where: {
        phoneHash: normalized.phoneHash,
        purpose: OtpPurpose.LOGIN,
        consumedAt: null,
      },
      data: {
        consumedAt: new Date(),
      },
    });

    const challenge = await prisma.otpChallenge.create({
      data: {
        phoneHash: normalized.phoneHash,
        phoneMasked: normalized.phoneMasked,
        otpHash,
        purpose: OtpPurpose.LOGIN,
        expiresAt,
        requestIp,
      },
    });

    try {
      await this.sms.sendOtp({
        e164Phone: normalized.e164,
        phoneMasked: normalized.phoneMasked,
        otpCode,
        lang: input.lang,
      });
    } catch (error) {
      // Roll back the challenge so user is not locked out by cooldown if SMS gateway failed
      await prisma.otpChallenge.delete({ where: { id: challenge.id } }).catch(() => undefined);
      throw error;
    }

    return {
      phoneMasked: normalized.phoneMasked,
      expiresInSeconds: env.OTP_EXPIRY_MINUTES * 60,
      resendCooldownSeconds: env.OTP_RESEND_COOLDOWN_SECONDS,
    };
  }

  /**
   * Step 2: Verify 6-digit OTP in constant time, enforce 5-minute TTL & max attempts,
   * create/fetch privacy-preserving user, and issue JWT session tokens.
   */
  public async verifyLoginOtp(input: VerifyOtpInput): Promise<AuthTokensResponse> {
    const normalized = normalizeAndHashAlgerianPhone(input.phone);

    const challenge = await prisma.otpChallenge.findFirst({
      where: {
        phoneHash: normalized.phoneHash,
        purpose: OtpPurpose.LOGIN,
        consumedAt: null,
      },
      orderBy: { createdAt: 'desc' },
    });

    if (!challenge || challenge.expiresAt.getTime() <= Date.now()) {
      throw new AppError(
        401,
        'OTP_INVALID_OR_EXPIRED',
        'Verification code is invalid or has expired. Please request a new code.',
      );
    }

    if (challenge.attempts >= env.OTP_MAX_ATTEMPTS) {
      throw new AppError(
        429,
        'OTP_MAX_ATTEMPTS_EXCEEDED',
        'Maximum verification attempts exceeded. Please request a new OTP code.',
      );
    }

    const isMatch = verifyOtpHashConstantTime(
      normalized.phoneHash,
      input.otp,
      challenge.otpHash,
    );

    if (!isMatch) {
      const updated = await prisma.otpChallenge.update({
        where: { id: challenge.id },
        data: { attempts: { increment: 1 } },
      });

      const remaining = Math.max(0, env.OTP_MAX_ATTEMPTS - updated.attempts);
      throw new AppError(
        401,
        'OTP_INVALID_OR_EXPIRED',
        remaining > 0
          ? `Incorrect verification code. ${remaining} attempt(s) remaining.`
          : 'Incorrect verification code. Maximum attempts reached.',
      );
    }

    // Consume OTP atomically and upsert user + session inside a transaction
    const result = await prisma.$transaction(async (tx) => {
      const consumeUpdate = await tx.otpChallenge.updateMany({
        where: {
          id: challenge.id,
          consumedAt: null,
        },
        data: {
          consumedAt: new Date(),
        },
      });

      if (consumeUpdate.count !== 1) {
        throw new AppError(
          401,
          'OTP_INVALID_OR_EXPIRED',
          'Verification code has already been used.',
        );
      }

      const user = await tx.user.upsert({
        where: { phoneHash: normalized.phoneHash },
        update: {
          phoneMasked: normalized.phoneMasked,
          preferredLang: input.lang,
        },
        create: {
          phoneHash: normalized.phoneHash,
          phoneMasked: normalized.phoneMasked,
          preferredLang: input.lang,
        },
      });

      if (!user.isActive) {
        throw new AppError(403, 'ACCOUNT_DISABLED', 'This account has been disabled.');
      }

      // Single-active-device policy for strict DRM protection:
      // Revoke older active sessions for this user when signing in on a new session
      await tx.session.updateMany({
        where: {
          userId: user.id,
          revokedAt: null,
        },
        data: {
          revokedAt: new Date(),
        },
      });

      const sessionExpiresAt = new Date(
        Date.now() + env.JWT_REFRESH_EXPIRES_IN_DAYS * 24 * 60 * 60 * 1000,
      );

      // Placeholder hash updated right after signing with session UUID
      const tempSession = await tx.session.create({
        data: {
          userId: user.id,
          refreshTokenHash: `pending_${challenge.id}`,
          devicePlatform: input.devicePlatform,
          fcmToken: input.fcmToken ?? null,
          expiresAt: sessionExpiresAt,
        },
      });

      const [accessToken, refreshToken] = await Promise.all([
        signAccessToken({
          userId: user.id,
          sessionId: tempSession.id,
          preferredLang: user.preferredLang,
        }),
        signRefreshToken({
          userId: user.id,
          sessionId: tempSession.id,
        }),
      ]);

      await tx.session.update({
        where: { id: tempSession.id },
        data: {
          refreshTokenHash: sha256Hex(refreshToken),
        },
      });

      return { user, accessToken, refreshToken };
    });

    return {
      accessToken: result.accessToken,
      refreshToken: result.refreshToken,
      expiresInSeconds: this.parseAccessExpirySeconds(),
      user: {
        id: result.user.id,
        phoneMasked: result.user.phoneMasked,
        preferredLang: result.user.preferredLang,
        createdAt: result.user.createdAt.toISOString(),
      },
    };
  }

  /**
   * Rotates Refresh Token & issues a fresh Access Token without requiring a new SMS OTP.
   */
  public async refreshSession(input: RefreshTokenInput): Promise<AuthTokensResponse> {
    const claims = await verifyRefreshToken(input.refreshToken);
    const incomingHash = sha256Hex(input.refreshToken);

    const session = await prisma.session.findUnique({
      where: { id: claims.sid },
      include: { user: true },
    });

    if (!session || session.userId !== claims.sub) {
      throw new AppError(401, 'UNAUTHORIZED', 'Invalid session.');
    }

    if (session.revokedAt !== null || session.expiresAt.getTime() <= Date.now()) {
      throw new AppError(401, 'UNAUTHORIZED', 'Session has expired. Please sign in again.');
    }

    // Token Replay Detection: if refresh token hash doesn't match, revoke session immediately!
    if (session.refreshTokenHash !== incomingHash) {
      await prisma.session.update({
        where: { id: session.id },
        data: { revokedAt: new Date() },
      });
      throw new AppError(
        401,
        'UNAUTHORIZED',
        'Refresh token reuse detected. Session has been terminated for security.',
      );
    }

    if (!session.user.isActive) {
      throw new AppError(403, 'ACCOUNT_DISABLED', 'This account has been disabled.');
    }

    const newExpiresAt = new Date(
      Date.now() + env.JWT_REFRESH_EXPIRES_IN_DAYS * 24 * 60 * 60 * 1000,
    );

    const [newAccessToken, newRefreshToken] = await Promise.all([
      signAccessToken({
        userId: session.user.id,
        sessionId: session.id,
        preferredLang: session.user.preferredLang,
      }),
      signRefreshToken({
        userId: session.user.id,
        sessionId: session.id,
      }),
    ]);

    await prisma.session.update({
      where: { id: session.id },
      data: {
        refreshTokenHash: sha256Hex(newRefreshToken),
        expiresAt: newExpiresAt,
        lastUsedAt: new Date(),
      },
    });

    return {
      accessToken: newAccessToken,
      refreshToken: newRefreshToken,
      expiresInSeconds: this.parseAccessExpirySeconds(),
      user: {
        id: session.user.id,
        phoneMasked: session.user.phoneMasked,
        preferredLang: session.user.preferredLang,
        createdAt: session.user.createdAt.toISOString(),
      },
    };
  }

  /**
   * Step 1 of changing phone number from Settings: sends OTP to the NEW Algerian number.
   */
  public async requestPhoneChangeOtp(
    userId: string,
    input: RequestChangePhoneInput,
    requestIp: string,
  ): Promise<{
    newPhoneMasked: string;
    expiresInSeconds: number;
    resendCooldownSeconds: number;
  }> {
    const normalized = normalizeAndHashAlgerianPhone(input.newPhone);

    const existingOwner = await prisma.user.findUnique({
      where: { phoneHash: normalized.phoneHash },
      select: { id: true },
    });

    if (existingOwner) {
      throw new AppError(
        409,
        'CONFLICT',
        'This Algerian phone number is already registered.',
      );
    }

    await this.enforceOtpCooldown(normalized.phoneHash, OtpPurpose.CHANGE_PHONE);

    const otpCode = generateSixDigitOtp();
    const otpHash = hashOtpCode(normalized.phoneHash, otpCode);
    const expiresAt = new Date(Date.now() + env.OTP_EXPIRY_MINUTES * 60 * 1000);

    await prisma.otpChallenge.updateMany({
      where: {
        phoneHash: normalized.phoneHash,
        purpose: OtpPurpose.CHANGE_PHONE,
        consumedAt: null,
      },
      data: { consumedAt: new Date() },
    });

    const challenge = await prisma.otpChallenge.create({
      data: {
        phoneHash: normalized.phoneHash,
        phoneMasked: normalized.phoneMasked,
        otpHash,
        purpose: OtpPurpose.CHANGE_PHONE,
        targetUserId: userId,
        expiresAt,
        requestIp,
      },
    });

    try {
      await this.sms.sendOtp({
        e164Phone: normalized.e164,
        phoneMasked: normalized.phoneMasked,
        otpCode,
        lang: input.lang,
      });
    } catch (error) {
      await prisma.otpChallenge.delete({ where: { id: challenge.id } }).catch(() => undefined);
      throw error;
    }

    return {
      newPhoneMasked: normalized.phoneMasked,
      expiresInSeconds: env.OTP_EXPIRY_MINUTES * 60,
      resendCooldownSeconds: env.OTP_RESEND_COOLDOWN_SECONDS,
    };
  }

  /**
   * Step 2 of changing phone number: verifies OTP and updates user's HMAC hash & mask.
   */
  public async confirmPhoneChange(
    userId: string,
    input: ConfirmChangePhoneInput,
  ): Promise<{ id: string; phoneMasked: string; preferredLang: string }> {
    const normalized = normalizeAndHashAlgerianPhone(input.newPhone);

    const challenge = await prisma.otpChallenge.findFirst({
      where: {
        phoneHash: normalized.phoneHash,
        purpose: OtpPurpose.CHANGE_PHONE,
        targetUserId: userId,
        consumedAt: null,
      },
      orderBy: { createdAt: 'desc' },
    });

    if (!challenge || challenge.expiresAt.getTime() <= Date.now()) {
      throw new AppError(
        401,
        'OTP_INVALID_OR_EXPIRED',
        'Verification code is invalid or expired.',
      );
    }

    if (challenge.attempts >= env.OTP_MAX_ATTEMPTS) {
      throw new AppError(
        429,
        'OTP_MAX_ATTEMPTS_EXCEEDED',
        'Maximum verification attempts exceeded.',
      );
    }

    const isMatch = verifyOtpHashConstantTime(
      normalized.phoneHash,
      input.otp,
      challenge.otpHash,
    );

    if (!isMatch) {
      await prisma.otpChallenge.update({
        where: { id: challenge.id },
        data: { attempts: { increment: 1 } },
      });
      throw new AppError(401, 'OTP_INVALID_OR_EXPIRED', 'Incorrect verification code.');
    }

    const updatedUser = await prisma.$transaction(async (tx) => {
      const conflict = await tx.user.findUnique({
        where: { phoneHash: normalized.phoneHash },
        select: { id: true },
      });
      if (conflict) {
        throw new AppError(409, 'CONFLICT', 'This phone number is already registered.');
      }

      await tx.otpChallenge.update({
        where: { id: challenge.id },
        data: { consumedAt: new Date() },
      });

      return tx.user.update({
        where: { id: userId },
        data: {
          phoneHash: normalized.phoneHash,
          phoneMasked: normalized.phoneMasked,
        },
        select: {
          id: true,
          phoneMasked: true,
          preferredLang: true,
        },
      });
    });

    return updatedUser;
  }

  private async enforceOtpCooldown(phoneHash: string, purpose: OtpPurpose): Promise<void> {
    const cooldownThreshold = new Date(
      Date.now() - env.OTP_RESEND_COOLDOWN_SECONDS * 1000,
    );

    const recentChallenge = await prisma.otpChallenge.findFirst({
      where: {
        phoneHash,
        purpose,
        createdAt: { gt: cooldownThreshold },
      },
      orderBy: { createdAt: 'desc' },
      select: { createdAt: true },
    });

    if (recentChallenge) {
      const elapsedSeconds = Math.floor(
        (Date.now() - recentChallenge.createdAt.getTime()) / 1000,
      );
      const waitSeconds = Math.max(1, env.OTP_RESEND_COOLDOWN_SECONDS - elapsedSeconds);
      throw new AppError(
        429,
        'OTP_COOLDOWN_ACTIVE',
        `Please wait ${waitSeconds} seconds before requesting another SMS code.`,
        { retryAfterSeconds: waitSeconds },
      );
    }
  }

  private parseAccessExpirySeconds(): number {
    const raw = env.JWT_ACCESS_EXPIRES_IN.trim();
    const match = /^(\d+)([smhd])$/.exec(raw);
    if (!match) return 900;
    const amount = Number(match[1]);
    switch (match[2]) {
      case 's':
        return amount;
      case 'm':
        return amount * 60;
      case 'h':
        return amount * 3600;
      case 'd':
        return amount * 86400;
      default:
        return 900;
    }
  }
}

export const authService = new AuthService();
