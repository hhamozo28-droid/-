import { z } from 'zod';

export const updateProfilePreferencesSchema = z.object({
  preferredLang: z.enum(['ar', 'fr', 'en']).optional(),
  fcmToken: z.string().trim().min(10).max(4096).nullable().optional(),
});

export type UpdateProfilePreferencesInput = z.infer<typeof updateProfilePreferencesSchema>;
