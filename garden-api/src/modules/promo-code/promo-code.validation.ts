import { z } from 'zod';

export const applyPromoCodeSchema = z.object({
  code: z.string().min(3).max(20).trim().toUpperCase(),
});
export type ApplyPromoCodeBody = z.infer<typeof applyPromoCodeSchema>;

/** POST /api/admin/promo-codes — sin UI propia todavía (ver comentario en
 * el schema de Prisma), pero ya queda administrable vía curl/Postman. */
export const createPromoCodeSchema = z.object({
  code: z.string().min(3).max(20).trim().toUpperCase(),
  discountType: z.enum(['PERCENT', 'FIXED']),
  discountValue: z.coerce.number().positive(),
  maxUses: z.coerce.number().int().positive().optional(),
  firstBookingOnly: z.boolean().optional().default(true),
  expiresAt: z.string().datetime().optional(),
});
export type CreatePromoCodeBody = z.infer<typeof createPromoCodeSchema>;
