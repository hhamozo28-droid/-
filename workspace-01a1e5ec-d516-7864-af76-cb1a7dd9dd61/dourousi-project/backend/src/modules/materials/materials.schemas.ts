import { z } from 'zod';

export const listMaterialsQuerySchema = z.object({
  search: z.string().trim().max(100).optional(),
  categoryPrefix: z.string().trim().toUpperCase().max(10).optional(),
  fileType: z.enum(['pdf', 'docx', 'zip']).optional(),
});

export const materialIdParamSchema = z.object({
  idOrCode: z.string().trim().min(1).max(64),
});

export const adminUpsertMaterialMetadataSchema = z.object({
  categoryPrefix: z
    .string()
    .trim()
    .toUpperCase()
    .regex(/^[A-Z]{2,10}$/, 'Category prefix must be 2-10 uppercase letters (e.g. ELE, BTP)'),
  categoryNameAr: z.string().trim().min(2).max(150).optional(),
  categoryNameFr: z.string().trim().min(2).max(150).optional(),
  categoryNameEn: z.string().trim().min(2).max(150).optional(),
  code: z
    .string()
    .trim()
    .toUpperCase()
    .regex(/^[A-Z0-9_-]{3,20}$/, 'Material code must be 3-20 alphanumeric characters (e.g. ELE0701)'),
  title: z.string().trim().min(2).max(255),
  contentLabel: z
    .string()
    .trim()
    .max(150)
    .default('مخططات الدروس (نموذج M9-1 — Word + PDF)'),
  unitsCount: z.coerce.number().int().min(1).max(500).default(1),
  lessonsCount: z.coerce.number().int().min(1).max(5000),
  filesCount: z.coerce.number().int().min(1).max(2000).default(1),
  pagesTotal: z.coerce.number().int().min(1).max(20000).default(1),
  fileType: z.enum(['pdf', 'docx', 'zip']).default('zip'),
  sourceUrl: z.string().url().optional(),
  notifyUsers: z
    .union([z.boolean(), z.enum(['true', 'false'])])
    .transform((v) => v === true || v === 'true')
    .default(true),
});

export const adminImportMarkdownBodySchema = z.object({
  markdown: z.string().min(20, 'Markdown table content is required'),
  notifyUsers: z.boolean().default(true),
});

export type ListMaterialsQuery = z.infer<typeof listMaterialsQuerySchema>;
export type AdminUpsertMaterialMetadata = z.infer<typeof adminUpsertMaterialMetadataSchema>;
export type AdminImportMarkdownBody = z.infer<typeof adminImportMarkdownBodySchema>;
