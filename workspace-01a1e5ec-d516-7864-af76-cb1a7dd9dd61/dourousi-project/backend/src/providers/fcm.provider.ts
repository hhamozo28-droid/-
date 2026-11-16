import { importPKCS8, SignJWT } from 'jose';
import { env } from '../config/env';
import { prisma } from '../config/prisma';

export interface LocalizedPushPayload {
  notificationId: string;
  materialId?: string | null;
  materialCode?: string | null;
  deepLink?: string | null;
  title: { ar: string; fr: string; en: string };
  body: { ar: string; fr: string; en: string };
}

/**
 * Lightweight, zero-dependency Firebase Cloud Messaging HTTP v1 dispatcher.
 * Sends each active device push notification in the user's preferred UI language (AR / FR / EN)
 * with deep link data so tapping opens the updated material directly.
 */
export class FcmProvider {
  private cachedAccessToken: { token: string; expiresAtMs: number } | null = null;

  public get isConfigured(): boolean {
    return Boolean(env.FCM_PROJECT_ID && env.FCM_CLIENT_EMAIL && env.FCM_PRIVATE_KEY);
  }

  public async broadcastMaterialNotification(payload: LocalizedPushPayload): Promise<{
    targetedDevices: number;
    deliveredCount: number;
  }> {
    const activeSessions = await prisma.session.findMany({
      where: {
        revokedAt: null,
        expiresAt: { gt: new Date() },
        fcmToken: { not: null },
        user: { isActive: true },
      },
      select: {
        id: true,
        fcmToken: true,
        user: {
          select: {
            preferredLang: true,
          },
        },
      },
    });

    if (activeSessions.length === 0) {
      return { targetedDevices: 0, deliveredCount: 0 };
    }

    if (!this.isConfigured) {
      console.info(
        `🔔 [DEV FCM Broadcast] Notification "${payload.title.ar}" queued for ${activeSessions.length} active device(s). DeepLink: ${payload.deepLink ?? 'N/A'}`,
      );
      return {
        targetedDevices: activeSessions.length,
        deliveredCount: activeSessions.length,
      };
    }

    const accessToken = await this.getGoogleOAuthAccessToken();
    const endpoint = `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(
      env.FCM_PROJECT_ID,
    )}/messages:send`;

    let deliveredCount = 0;

    await Promise.allSettled(
      activeSessions.map(async (session) => {
        if (!session.fcmToken) return;
        const lang = (['ar', 'fr', 'en'].includes(session.user.preferredLang)
          ? session.user.preferredLang
          : 'ar') as 'ar' | 'fr' | 'en';

        const response = await fetch(endpoint, {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${accessToken}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            message: {
              token: session.fcmToken,
              notification: {
                title: payload.title[lang],
                body: payload.body[lang],
              },
              data: {
                notificationId: payload.notificationId,
                materialId: payload.materialId ?? '',
                materialCode: payload.materialCode ?? '',
                deepLink: payload.deepLink ?? '',
              },
              android: {
                priority: 'HIGH',
              },
              apns: {
                headers: {
                  'apns-priority': '10',
                },
              },
            },
          }),
          signal: AbortSignal.timeout(10_000),
        });

        if (response.ok) {
          deliveredCount += 1;
        } else if (response.status === 404 || response.status === 410) {
          // Prune unregistered/expired FCM token automatically
          await prisma.session
            .update({
              where: { id: session.id },
              data: { fcmToken: null },
            })
            .catch(() => undefined);
        }
      }),
    );

    return {
      targetedDevices: activeSessions.length,
      deliveredCount,
    };
  }

  private async getGoogleOAuthAccessToken(): Promise<string> {
    if (
      this.cachedAccessToken &&
      this.cachedAccessToken.expiresAtMs > Date.now() + 60_000
    ) {
      return this.cachedAccessToken.token;
    }

    const normalizedPrivateKey = env.FCM_PRIVATE_KEY.replace(/\\n/g, '\n');
    const privateKey = await importPKCS8(normalizedPrivateKey, 'RS256');

    const assertion = await new SignJWT({
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
    })
      .setProtectedHeader({ alg: 'RS256', typ: 'JWT' })
      .setIssuer(env.FCM_CLIENT_EMAIL)
      .setSubject(env.FCM_CLIENT_EMAIL)
      .setAudience('https://oauth2.googleapis.com/token')
      .setIssuedAt()
      .setExpirationTime('1h')
      .sign(privateKey);

    const tokenRes = await fetch('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        assertion,
      }).toString(),
      signal: AbortSignal.timeout(10_000),
    });

    if (!tokenRes.ok) {
      throw new Error(`Failed to obtain Google OAuth2 token for FCM (HTTP ${tokenRes.status})`);
    }

    const json = (await tokenRes.json()) as { access_token: string; expires_in: number };
    this.cachedAccessToken = {
      token: json.access_token,
      expiresAtMs: Date.now() + json.expires_in * 1000,
    };

    return json.access_token;
  }
}

export const fcmProvider = new FcmProvider();
