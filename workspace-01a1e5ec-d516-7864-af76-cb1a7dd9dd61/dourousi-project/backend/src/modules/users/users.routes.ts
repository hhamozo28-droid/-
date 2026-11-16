import { FastifyInstance } from 'fastify';
import { requireAuth } from '../../common/middlewares/auth.guard';
import { updateProfilePreferencesSchema } from './users.schemas';
import { usersService } from './users.service';

export async function usersRoutes(app: FastifyInstance): Promise<void> {
  /**
   * GET /me
   * Returns current authenticated user's privacy-safe profile
   */
  app.get(
    '/me',
    { preHandler: [requireAuth] },
    async (request, reply) => {
      const profile = await usersService.getCurrentUser(
        request.auth!.userId,
        request.auth!.sessionId,
      );
      return reply.status(200).send({
        success: true,
        data: profile,
      });
    },
  );

  /**
   * PATCH /me/preferences
   * Updates preferred UI language ('ar' | 'fr' | 'en') or registers FCM push token
   */
  app.patch(
    '/me/preferences',
    { preHandler: [requireAuth] },
    async (request, reply) => {
      const input = updateProfilePreferencesSchema.parse(request.body);
      const profile = await usersService.updatePreferences(
        request.auth!.userId,
        request.auth!.sessionId,
        input,
      );
      return reply.status(200).send({
        success: true,
        data: profile,
      });
    },
  );

  /**
   * POST /logout
   * Revokes active JWT session immediately
   */
  app.post(
    '/logout',
    { preHandler: [requireAuth] },
    async (request, reply) => {
      await usersService.logoutSession(request.auth!.sessionId);
      return reply.status(200).send({
        success: true,
        data: { message: 'Logged out successfully.' },
      });
    },
  );

  /**
   * DELETE /me
   * Permanently deletes user account and all server-side session records
   */
  app.delete(
    '/me',
    { preHandler: [requireAuth] },
    async (request, reply) => {
      await usersService.deleteAccountPermanently(request.auth!.userId);
      return reply.status(200).send({
        success: true,
        data: { message: 'Account and associated records permanently deleted.' },
      });
    },
  );
}
