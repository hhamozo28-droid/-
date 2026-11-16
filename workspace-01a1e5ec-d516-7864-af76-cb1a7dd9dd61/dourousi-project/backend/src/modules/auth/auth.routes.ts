import { FastifyInstance } from 'fastify';
import { requireAuth } from '../../common/middlewares/auth.guard';
import {
  confirmChangePhoneBodySchema,
  refreshTokenBodySchema,
  requestChangePhoneBodySchema,
  sendOtpBodySchema,
  verifyOtpBodySchema,
} from './auth.schemas';
import { authService } from './auth.service';

export async function authRoutes(app: FastifyInstance): Promise<void> {
  /**
   * POST /auth/send-otp
   * Strict IP rate-limit (max 5 SMS requests per 10 minutes per IP) to prevent SMS pumping
   */
  app.post(
    '/auth/send-otp',
    {
      config: {
        rateLimit: {
          max: 5,
          timeWindow: '10 minutes',
        },
      },
    },
    async (request, reply) => {
      const input = sendOtpBodySchema.parse(request.body);
      const result = await authService.sendLoginOtp(input, request.ip);
      return reply.status(200).send({
        success: true,
        data: result,
      });
    },
  );

  /**
   * POST /auth/verify-otp
   * Verifies the 6-digit OTP and returns JWT Access + Refresh tokens
   */
  app.post(
    '/auth/verify-otp',
    {
      config: {
        rateLimit: {
          max: 10,
          timeWindow: '10 minutes',
        },
      },
    },
    async (request, reply) => {
      const input = verifyOtpBodySchema.parse(request.body);
      const result = await authService.verifyLoginOtp(input);
      return reply.status(200).send({
        success: true,
        data: result,
      });
    },
  );

  /**
   * POST /auth/refresh
   * Rotates refresh token and issues a fresh access token
   */
  app.post(
    '/auth/refresh',
    {
      config: {
        rateLimit: {
          max: 20,
          timeWindow: '5 minutes',
        },
      },
    },
    async (request, reply) => {
      const input = refreshTokenBodySchema.parse(request.body);
      const result = await authService.refreshSession(input);
      return reply.status(200).send({
        success: true,
        data: result,
      });
    },
  );

  /**
   * POST /auth/change-phone/send-otp
   * Authenticated endpoint to initiate changing the user's Algerian phone number
   */
  app.post(
    '/auth/change-phone/send-otp',
    {
      preHandler: [requireAuth],
      config: {
        rateLimit: {
          max: 3,
          timeWindow: '15 minutes',
        },
      },
    },
    async (request, reply) => {
      const input = requestChangePhoneBodySchema.parse(request.body);
      const result = await authService.requestPhoneChangeOtp(
        request.auth!.userId,
        input,
        request.ip,
      );
      return reply.status(200).send({
        success: true,
        data: result,
      });
    },
  );

  /**
   * POST /auth/change-phone/confirm
   * Authenticated endpoint to confirm OTP and migrate account to the new Algerian number
   */
  app.post(
    '/auth/change-phone/confirm',
    {
      preHandler: [requireAuth],
      config: {
        rateLimit: {
          max: 8,
          timeWindow: '15 minutes',
        },
      },
    },
    async (request, reply) => {
      const input = confirmChangePhoneBodySchema.parse(request.body);
      const result = await authService.confirmPhoneChange(request.auth!.userId, input);
      return reply.status(200).send({
        success: true,
        data: result,
      });
    },
  );
}
