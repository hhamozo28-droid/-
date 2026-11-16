import { z } from 'zod';

export const uiLanguageSchema = z.enum(['ar', 'fr', 'en']).default('ar');
export const devicePlatformSchema = z.enum(['android', 'ios']).default('android');

export const sendOtpBodySchema = z.object({
  phone: z
    .string()
    .min(9, 'Algerian phone number is too short')
    .max(20, 'Phone number is too long'),
  lang: uiLanguageSchema,
});

export const verifyOtpBodySchema = z.object({
  phone: z.string().min(9).max(20),
  otp: z
    .string()
    .trim()
    .regex(/^\d{6}$/, 'OTP code must consist of exactly 6 digits'),
  devicePlatform: devicePlatformSchema,
  fcmToken: z.string().trim().min(10).max(4096).optional(),
  lang: uiLanguageSchema,
});

export const refreshTokenBodySchema = z.object({
  refreshToken: z.string().min(20, 'Refresh token is required'),
});

export const requestChangePhoneBodySchema = z.object({
  newPhone: z.string().min(9).max(20),
  lang: uiLanguageSchema,
});

export const confirmChangePhoneBodySchema = z.object({
  newPhone: z.string().min(9).max(20),
  otp: z
    .string()
    .trim()
    .regex(/^\d{6}$/, 'OTP code must consist of exactly 6 digits'),
});

export type SendOtpInput = z.infer<typeof sendOtpBodySchema>;
export type VerifyOtpInput = z.infer<typeof verifyOtpBodySchema>;
export type RefreshTokenInput = z.infer<typeof refreshTokenBodySchema>;
export type RequestChangePhoneInput = z.infer<typeof requestChangePhoneBodySchema>;
export type ConfirmChangePhoneInput = z.infer<typeof confirmChangePhoneBodySchema>;
