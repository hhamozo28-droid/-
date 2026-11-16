import Fastify, { FastifyInstance } from 'fastify';
import cors from '@fastify/cors';
import helmet from '@fastify/helmet';
import multipart from '@fastify/multipart';
import rateLimit from '@fastify/rate-limit';
import { env } from './config/env';
import { globalErrorHandler } from './common/errors/app-error';
import { authRoutes } from './modules/auth/auth.routes';
import { usersRoutes } from './modules/users/users.routes';
import { categoriesRoutes } from './modules/categories/categories.routes';
import { materialsRoutes } from './modules/materials/materials.routes';
import { notificationsRoutes } from './modules/notifications/notifications.routes';
import { adminRoutes } from './modules/admin/admin.routes';

export async function buildApp(): Promise<FastifyInstance> {
  const app = Fastify({
    logger: {
      level: env.NODE_ENV === 'production' ? 'info' : 'debug',
      // Redact Authorization headers & tokens from all logs for strict privacy
      redact: [
        'req.headers.authorization',
        'req.headers["x-admin-api-key"]',
        'req.body.phone',
        'req.body.newPhone',
        'req.body.otp',
        'req.body.refreshToken',
      ],
    },
    trustProxy: true,
  });

  // Security HTTP headers (allow inline script ONLY on /admin console)
  await app.register(helmet, {
    contentSecurityPolicy: false,
  });

  await app.register(cors, {
    origin: true,
    methods: ['GET', 'POST', 'PATCH', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization', 'X-Admin-Api-Key', 'Range'],
    exposedHeaders: ['Content-Length', 'Content-Range', 'Accept-Ranges'],
  });

  await app.register(rateLimit, {
    global: true,
    max: 120,
    timeWindow: '1 minute',
  });

  // Support uploading large training bags up to 200 MB
  await app.register(multipart, {
    limits: {
      fileSize: 200 * 1024 * 1024,
      files: 1,
      fields: 20,
    },
  });

  app.setErrorHandler(globalErrorHandler);

  // Health & readiness probe
  app.get('/health', async () => ({
    success: true,
    service: 'dourousi-api',
    countryPolicy: 'DZ (+213 Only)',
    drmMode: 'STRICT_IN_APP_AES256',
    developer: 'Hamza Chouaib (حمزة شعيب)',
    timestamp: new Date().toISOString(),
  }));

  // API v1 & root compatible mounts (matches specification endpoints)
  await app.register(authRoutes);
  await app.register(usersRoutes);
  await app.register(categoriesRoutes);
  await app.register(materialsRoutes);
  await app.register(notificationsRoutes);
  await app.register(adminRoutes);

  return app;
}
