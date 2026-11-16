import { FastifyInstance } from 'fastify';
import { prisma } from '../../config/prisma';
import { requireAuth } from '../../common/middlewares/auth.guard';

export async function categoriesRoutes(app: FastifyInstance): Promise<void> {
  /**
   * GET /categories
   * Lists all vocational training branches (ELE, AGR, ART, BTP, MEE...) with active material counts.
   */
  app.get(
    '/categories',
    { preHandler: [requireAuth] },
    async (_request, reply) => {
      const categories = await prisma.category.findMany({
        orderBy: [{ sortOrder: 'asc' }, { prefixCode: 'asc' }],
        include: {
          _count: {
            select: {
              materials: {
                where: { isActive: true },
              },
            },
          },
        },
      });

      const formatted = categories.map((cat) => ({
        id: cat.id,
        prefixCode: cat.prefixCode,
        nameAr: cat.nameAr,
        nameFr: cat.nameFr,
        nameEn: cat.nameEn,
        sortOrder: cat.sortOrder,
        materialsCount: cat._count.materials,
      }));

      return reply.status(200).send({
        success: true,
        data: formatted,
      });
    },
  );
}
