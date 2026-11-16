import { prisma } from '../../config/prisma';
import { AppError } from '../../common/errors/app-error';
import { UpdateProfilePreferencesInput } from './users.schemas';

export class UsersService {
  /**
   * GET /me: Returns privacy-safe user profile (masked phone only, never raw phone or hash).
   */
  public async getCurrentUser(userId: string, sessionId: string) {
    const user = await prisma.user.findUnique({
      where: { id: userId },
      select: {
        id: true,
        phoneMasked: true,
        preferredLang: true,
        createdAt: true,
        updatedAt: true,
      },
    });

    if (!user) {
      throw new AppError(404, 'NOT_FOUND', 'User profile not found.');
    }

    return {
      id: user.id,
      phoneMasked: user.phoneMasked,
      preferredLang: user.preferredLang,
      currentSessionId: sessionId,
      countryCode: '+213',
      developer: 'حمزة شعيب (Hamza Chouaib)',
      createdAt: user.createdAt.toISOString(),
      updatedAt: user.updatedAt.toISOString(),
    };
  }

  /**
   * PATCH /me/preferences: Updates UI language preference (for localized FCM pushes)
   * and/or updates the device's Firebase Cloud Messaging token.
   */
  public async updatePreferences(
    userId: string,
    sessionId: string,
    input: UpdateProfilePreferencesInput,
  ) {
    await prisma.$transaction(async (tx) => {
      if (input.preferredLang !== undefined) {
        await tx.user.update({
          where: { id: userId },
          data: { preferredLang: input.preferredLang },
        });
      }

      if (input.fcmToken !== undefined) {
        await tx.session.update({
          where: { id: sessionId },
          data: { fcmToken: input.fcmToken },
        });
      }
    });

    return this.getCurrentUser(userId, sessionId);
  }

  /**
   * POST /logout: Immediately revokes the current session and clears its FCM token
   * so logged-out devices never receive push notifications.
   */
  public async logoutSession(sessionId: string): Promise<void> {
    await prisma.session.updateMany({
      where: { id: sessionId, revokedAt: null },
      data: {
        revokedAt: new Date(),
        fcmToken: null,
      },
    });
  }

  /**
   * DELETE /me: Permanently deletes user account & cascades all sessions
   * (Mandatory for Google Play & Apple App Store privacy compliance).
   */
  public async deleteAccountPermanently(userId: string): Promise<void> {
    await prisma.user.delete({
      where: { id: userId },
    });
  }
}

export const usersService = new UsersService();
