import { FastifyReply, FastifyRequest } from 'fastify';
import { prisma } from '../../config/prisma';
import { verifyAccessToken, verifyAdminApiKey } from '../crypto/security';
import { AppError } from '../errors/app-error';

export interface AuthenticatedPrincipal {
  userId: string;
  sessionId: string;
  preferredLang: string;
}

declare module 'fastify' {
  interface FastifyRequest {
    auth?: AuthenticatedPrincipal;
  }
}

/**
 * Protects user routes by verifying the Bearer JWT Access Token
 * AND validating that the session has not been revoked or user disabled.
 */
export async function requireAuth(
  request: FastifyRequest,
  _reply: FastifyReply,
): Promise<void> {
  const authHeader = request.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    throw new AppError(401, 'UNAUTHORIZED', 'Missing or malformed Authorization Bearer header.');
  }

  const token = authHeader.slice(7).trim();
  if (!token) {
    throw new AppError(401, 'UNAUTHORIZED', 'Empty Bearer token.');
  }

  const claims = await verifyAccessToken(token);

  const session = await prisma.session.findUnique({
    where: { id: claims.sid },
    select: {
      id: true,
      userId: true,
      revokedAt: true,
      expiresAt: true,
      user: {
        select: {
          id: true,
          isActive: true,
          preferredLang: true,
        },
      },
    },
  });

  if (!session || session.userId !== claims.sub) {
    throw new AppError(401, 'UNAUTHORIZED', 'Session does not exist.');
  }

  if (session.revokedAt !== null || session.expiresAt.getTime() <= Date.now()) {
    throw new AppError(401, 'UNAUTHORIZED', 'Session has expired or been logged out.');
  }

  if (!session.user.isActive) {
    throw new AppError(403, 'ACCOUNT_DISABLED', 'This user account has been disabled.');
  }

  request.auth = {
    userId: session.user.id,
    sessionId: session.id,
    preferredLang: session.user.preferredLang,
  };
}

/**
 * Protects administrative endpoints (uploading/updating materials & pushing notifications)
 * using constant-time verification of X-Admin-Api-Key header.
 */
export async function requireAdminKey(
  request: FastifyRequest,
  _reply: FastifyReply,
): Promise<void> {
  const rawKey = request.headers['x-admin-api-key'];
  const providedKey = Array.isArray(rawKey) ? rawKey[0] : rawKey;

  if (!providedKey || !verifyAdminApiKey(providedKey)) {
    throw new AppError(403, 'FORBIDDEN', 'Invalid or missing X-Admin-Api-Key.');
  }
}
