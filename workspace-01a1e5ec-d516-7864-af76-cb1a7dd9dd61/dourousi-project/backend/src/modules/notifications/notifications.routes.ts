import { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { prisma } from '../../config/prisma';
import { requireAuth } from '../../common/middlewares/auth.guard';

const listNotificationsQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(50),
  since: z.string().datetime().optional(),
});

export async function notificationsRoutes(app: FastifyInstance): Promise<void> {
  /**
   * GET /notifications
   * Returns localized update log (new materials, updated versions, system notices)
   * with direct deep link & material code for one-tap opening in Flutter.
   */
  app.get(
    '/notifications',
    { preHandler: [requireAuth] },
    async (request, reply) => {
      const query = listNotificationsQuerySchema.parse(request.query);

      const items = await prisma.notification.findMany({
        where: query.since ? { createdAt: { gt: new Date(query.since) } } : undefined,
        orderBy: { createdAt: 'desc' },
        take: query.limit,
        include: {
          material: {
            select: {
              id: true,
              code: true,
              title: true,
              version: true,
              fileType: true,
            },
          },
        },
      });

      const formatted = items.map((n) => ({
        id: n.id,
        type: n.type,
        title: {
          ar: n.titleAr,
          fr: n.titleFr,
          en: n.titleEn,
        },
        body: {
          ar: n.bodyAr,
          fr: n.bodyFr,
          en: n.bodyEn,
        },
        deepLink: n.deepLink,
        material: n.material,
        createdAt: n.createdAt.toISOString(),
      }));

      return reply.status(200).send({
        success: true,
        count: formatted.length,
        data: formatted,
      });
    },
  );
}
