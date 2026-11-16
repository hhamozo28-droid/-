import { FastifyError, FastifyReply, FastifyRequest } from 'fastify';
import { ZodError } from 'zod';

export type ErrorCode =
  | 'VALIDATION_ERROR'
  | 'INVALID_ALGERIAN_PHONE'
  | 'OTP_COOLDOWN_ACTIVE'
  | 'OTP_INVALID_OR_EXPIRED'
  | 'OTP_MAX_ATTEMPTS_EXCEEDED'
  | 'UNAUTHORIZED'
  | 'FORBIDDEN'
  | 'ACCOUNT_DISABLED'
  | 'NOT_FOUND'
  | 'CONFLICT'
  | 'RATE_LIMIT_EXCEEDED'
  | 'SMS_DELIVERY_FAILED'
  | 'STORAGE_ERROR'
  | 'INTERNAL_SERVER_ERROR';

export class AppError extends Error {
  public readonly statusCode: number;
  public readonly code: ErrorCode;
  public readonly details?: unknown;

  constructor(statusCode: number, code: ErrorCode, message: string, details?: unknown) {
    super(message);
    this.name = 'AppError';
    this.statusCode = statusCode;
    this.code = code;
    this.details = details;
    Object.setPrototypeOf(this, new.target.prototype);
  }
}

export function globalErrorHandler(
  error: FastifyError | AppError | ZodError | Error,
  request: FastifyRequest,
  reply: FastifyReply,
): void {
  if (error instanceof AppError) {
    reply.status(error.statusCode).send({
      success: false,
      error: {
        code: error.code,
        message: error.message,
        ...(error.details !== undefined ? { details: error.details } : {}),
      },
    });
    return;
  }

  if (error instanceof ZodError) {
    reply.status(400).send({
      success: false,
      error: {
        code: 'VALIDATION_ERROR' satisfies ErrorCode,
        message: 'Invalid request payload or parameters.',
        details: error.flatten().fieldErrors,
      },
    });
    return;
  }

  const fastifyErr = error as FastifyError;
  if (fastifyErr.statusCode === 429) {
    reply.status(429).send({
      success: false,
      error: {
        code: 'RATE_LIMIT_EXCEEDED' satisfies ErrorCode,
        message: 'Too many requests. Please wait before trying again.',
      },
    });
    return;
  }

  request.log.error({ err: error, url: request.url, method: request.method }, 'Unhandled server error');

  reply.status(500).send({
    success: false,
    error: {
      code: 'INTERNAL_SERVER_ERROR' satisfies ErrorCode,
      message: 'An unexpected server error occurred.',
    },
  });
}
