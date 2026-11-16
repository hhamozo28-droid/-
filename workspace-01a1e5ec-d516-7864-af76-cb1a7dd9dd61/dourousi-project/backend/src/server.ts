import { buildApp } from './app';
import { env } from './config/env';
import { prisma } from './config/prisma';

async function bootstrap(): Promise<void> {
  const app = await buildApp();

  const shutdown = async (signal: string) => {
    app.log.info(`Received ${signal}. Gracefully shutting down Dourousi server...`);
    await app.close();
    await prisma.$disconnect();
    process.exit(0);
  };

  process.on('SIGINT', () => void shutdown('SIGINT'));
  process.on('SIGTERM', () => void shutdown('SIGTERM'));

  try {
    await app.listen({ host: env.HOST, port: env.PORT });
    app.log.info(
      `🚀 Dourousi Backend listening on http://${env.HOST}:${env.PORT} [Algeria +213 Only | Strict DRM]`,
    );
  } catch (err) {
    app.log.error(err, 'Failed to start Dourousi Backend');
    await prisma.$disconnect();
    process.exit(1);
  }
}

void bootstrap();
