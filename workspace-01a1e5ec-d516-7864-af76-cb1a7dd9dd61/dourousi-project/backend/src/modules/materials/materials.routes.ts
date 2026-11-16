import fs from 'node:fs';
import fsp from 'node:fs/promises';
import { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { requireAdminKey, requireAuth } from '../../common/middlewares/auth.guard';
import { AppError } from '../../common/errors/app-error';
import {
  localVaultProvider,
  verifyLocalDownloadToken,
} from '../../providers/storage.provider';
import {
  adminImportMarkdownBodySchema,
  adminUpsertMaterialMetadataSchema,
  listMaterialsQuerySchema,
  materialIdParamSchema,
} from './materials.schemas';
import { materialsService } from './materials.service';

export async function materialsRoutes(app: FastifyInstance): Promise<void> {
  app.get(
    '/materials',
    { preHandler: [requireAuth] },
    async (request, reply) => {
      const query = listMaterialsQuerySchema.parse(request.query);
      const list = await materialsService.listMaterials(query);
      return reply.status(200).send({
        success: true,
        count: list.length,
        data: list,
      });
    },
  );

  app.get(
    '/materials/:idOrCode',
    { preHandler: [requireAuth] },
    async (request, reply) => {
      const { idOrCode } = materialIdParamSchema.parse(request.params);
      const material = await materialsService.getMaterialByIdOrCode(idOrCode);
      return reply.status(200).send({
        success: true,
        data: material,
      });
    },
  );

  app.get(
    '/materials/:idOrCode/download',
    {
      preHandler: [requireAuth],
      config: {
        rateLimit: {
          max: 30,
          timeWindow: '5 minutes',
        },
      },
    },
    async (request, reply) => {
      const { idOrCode } = materialIdParamSchema.parse(request.params);
      const protocol =
        (request.headers['x-forwarded-proto'] as string | undefined)?.split(',')[0] ??
        request.protocol;
      const host = request.headers.host ?? 'localhost:3000';
      const requestBaseUrl = `${protocol}://${host}`;

      const payload = await materialsService.createSignedDownloadPayload({
        idOrCode,
        userId: request.auth!.userId,
        requestBaseUrl,
      });

      return reply.status(200).send({
        success: true,
        data: payload,
      });
    },
  );

  /**
   * GET /vault/stream?token=...
   * Protected binary streaming endpoint with full HTTP Range support (206 Partial Content).
   */
  app.get('/vault/stream', async (request, reply) => {
    const querySchema = z.object({ token: z.string().min(10) });
    const { token } = querySchema.parse(request.query);
    const verified = await verifyLocalDownloadToken(token);

    const filePath = localVaultProvider.resolveSafePath(verified.storageKey);
    const stat = await fsp.stat(filePath).catch(() => null);

    if (!stat || !stat.isFile()) {
      throw new AppError(404, 'NOT_FOUND', 'Material file binary not found in storage vault.');
    }

    const totalSize = stat.size;
    const rangeHeader = request.headers.range;

    reply.header('Accept-Ranges', 'bytes');
    reply.header('Cache-Control', 'private, no-store');
    reply.header('X-Content-Type-Options', 'nosniff');

    if (rangeHeader) {
      const match = /^bytes=(\d+)-(\d*)$/.exec(rangeHeader.trim());
      if (!match) {
        reply.header('Content-Range', `bytes */${totalSize}`);
        return reply.status(416).send();
      }

      const start = Number(match[1]);
      const end = match[2] ? Math.min(Number(match[2]), totalSize - 1) : totalSize - 1;

      if (start >= totalSize || start > end) {
        reply.header('Content-Range', `bytes */${totalSize}`);
        return reply.status(416).send();
      }

      const chunkSize = end - start + 1;
      reply.status(206);
      reply.header('Content-Range', `bytes ${start}-${end}/${totalSize}`);
      reply.header('Content-Length', chunkSize);
      reply.header('Content-Type', 'application/octet-stream');

      return reply.send(fs.createReadStream(filePath, { start, end }));
    }

    reply.status(200);
    reply.header('Content-Length', totalSize);
    reply.header('Content-Type', 'application/octet-stream');
    return reply.send(fs.createReadStream(filePath));
  });

  /**
   * POST /admin/materials/upload
   * Admin multipart upload endpoint (up to 200MB) for a specialty's M9-1 ZIP/PDF/DOCX file.
   */
  app.post(
    '/admin/materials/upload',
    { preHandler: [requireAdminKey] },
    async (request, reply) => {
      const fields: Record<string, string> = {};
      let uploadedResult: Awaited<
        ReturnType<typeof materialsService.adminUploadOrUpdateMaterial>
      > | null = null;

      const parts = request.parts();
      for await (const part of parts) {
        if (part.type === 'field') {
          fields[part.fieldname] = String(part.value ?? '');
        } else if (part.type === 'file' && part.fieldname === 'file') {
          const metadata = adminUpsertMaterialMetadataSchema.parse(fields);
          uploadedResult = await materialsService.adminUploadOrUpdateMaterial({
            metadata,
            fileStream: part.file,
            mimeType: part.mimetype || 'application/octet-stream',
          });
        }
      }

      if (!uploadedResult) {
        throw new AppError(
          400,
          'VALIDATION_ERROR',
          'Multipart form must include metadata fields BEFORE the "file" field.',
        );
      }

      return reply.status(200).send({
        success: true,
        data: uploadedResult,
      });
    },
  );

  /**
   * POST /admin/materials/import-markdown
   * Bulk imports Professor Hamza Chouaib's `روابط التحميل.txt` Markdown table in 1 click!
   */
  app.post(
    '/admin/materials/import-markdown',
    { preHandler: [requireAdminKey] },
    async (request, reply) => {
      const body = adminImportMarkdownBodySchema.parse(request.body);
      const summary = await materialsService.adminBulkImportFromMarkdown(body);
      return reply.status(200).send({
        success: true,
        data: summary,
      });
    },
  );
}
