import crypto from 'node:crypto';
import { SignJWT, jwtVerify, JWTPayload } from 'jose';
import { env } from '../../config/env';
import { AppError } from '../errors/app-error';

const accessSecretKey = new TextEncoder().encode(env.JWT_ACCESS_SECRET);
const refreshSecretKey = new TextEncoder().encode(env.JWT_REFRESH_SECRET);

const JWT_ISSUER = 'dourousi-api';
const JWT_AUDIENCE = 'dourousi-mobile';

export interface AccessTokenClaims extends JWTPayload {
  sub: string;       // User UUID
  sid: string;       // Session UUID
  lang: string;      // Preferred language ('ar' | 'fr' | 'en')
  type: 'access';
}

export interface RefreshTokenClaims extends JWTPayload {
  sub: string;       // User UUID
  sid: string;       // Session UUID
  jti: string;       // Unique token nonce for rotation
  type: 'refresh';
}

/**
 * Generates a cryptographically secure 6-digit OTP code (100000 - 999999)
 */
export function generateSixDigitOtp(): string {
  const num = crypto.randomInt(100000, 1000000);
  return num.toString();
}

/**
 * Computes HMAC-SHA256 of an OTP bound to the phoneHash so an OTP hash
 * cannot be transplanted across challenges.
 */
export function hashOtpCode(phoneHash: string, otpCode: string): string {
  return crypto
    .createHmac('sha256', env.OTP_HMAC_SECRET)
    .update(`${phoneHash}:${otpCode}`, 'utf8')
    .digest('hex');
}

/**
 * Constant-time verification of OTP hash to prevent timing side-channel attacks.
 */
export function verifyOtpHashConstantTime(
  phoneHash: string,
  candidateOtp: string,
  expectedHashHex: string,
): boolean {
  const candidateHashHex = hashOtpCode(phoneHash, candidateOtp);
  const a = Buffer.from(candidateHashHex, 'hex');
  const b = Buffer.from(expectedHashHex, 'hex');
  if (a.length !== b.length) {
    return false;
  }
  return crypto.timingSafeEqual(a, b);
}

/**
 * Hashes refresh tokens or download tokens with SHA-256 before DB storage.
 */
export function sha256Hex(value: string): string {
  return crypto.createHash('sha256').update(value, 'utf8').digest('hex');
}

/**
 * Signs a short-lived JWT Access Token.
 */
export async function signAccessToken(params: {
  userId: string;
  sessionId: string;
  preferredLang: string;
}): Promise<string> {
  return new SignJWT({
    sid: params.sessionId,
    lang: params.preferredLang,
    type: 'access',
  })
    .setProtectedHeader({ alg: 'HS256', typ: 'JWT' })
    .setSubject(params.userId)
    .setIssuer(JWT_ISSUER)
    .setAudience(JWT_AUDIENCE)
    .setIssuedAt()
    .setExpirationTime(env.JWT_ACCESS_EXPIRES_IN)
    .sign(accessSecretKey);
}

/**
 * Signs a rotatable JWT Refresh Token.
 */
export async function signRefreshToken(params: {
  userId: string;
  sessionId: string;
}): Promise<string> {
  const jti = crypto.randomUUID();
  return new SignJWT({
    sid: params.sessionId,
    type: 'refresh',
  })
    .setProtectedHeader({ alg: 'HS256', typ: 'JWT' })
    .setSubject(params.userId)
    .setJti(jti)
    .setIssuer(JWT_ISSUER)
    .setAudience(JWT_AUDIENCE)
    .setIssuedAt()
    .setExpirationTime(`${env.JWT_REFRESH_EXPIRES_IN_DAYS}d`)
    .sign(refreshSecretKey);
}

export async function verifyAccessToken(token: string): Promise<AccessTokenClaims> {
  try {
    const { payload } = await jwtVerify(token, accessSecretKey, {
      issuer: JWT_ISSUER,
      audience: JWT_AUDIENCE,
      algorithms: ['HS256'],
    });

    if (
      payload.type !== 'access' ||
      typeof payload.sub !== 'string' ||
      typeof payload.sid !== 'string'
    ) {
      throw new AppError(401, 'UNAUTHORIZED', 'Invalid access token claims.');
    }

    return payload as AccessTokenClaims;
  } catch (err) {
    if (err instanceof AppError) throw err;
    throw new AppError(401, 'UNAUTHORIZED', 'Access token is invalid or expired.');
  }
}

export async function verifyRefreshToken(token: string): Promise<RefreshTokenClaims> {
  try {
    const { payload } = await jwtVerify(token, refreshSecretKey, {
      issuer: JWT_ISSUER,
      audience: JWT_AUDIENCE,
      algorithms: ['HS256'],
    });

    if (
      payload.type !== 'refresh' ||
      typeof payload.sub !== 'string' ||
      typeof payload.sid !== 'string' ||
      typeof payload.jti !== 'string'
    ) {
      throw new AppError(401, 'UNAUTHORIZED', 'Invalid refresh token claims.');
    }

    return payload as RefreshTokenClaims;
  } catch (err) {
    if (err instanceof AppError) throw err;
    throw new AppError(401, 'UNAUTHORIZED', 'Refresh token is invalid or expired.');
  }
}

/**
 * Constant-time comparison for Admin API Key verification.
 */
export function verifyAdminApiKey(providedKey: string): boolean {
  const hashA = crypto.createHash('sha256').update(providedKey, 'utf8').digest();
  const hashB = crypto.createHash('sha256').update(env.ADMIN_API_KEY, 'utf8').digest();
  return crypto.timingSafeEqual(hashA, hashB);
}
