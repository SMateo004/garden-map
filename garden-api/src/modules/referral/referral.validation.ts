import { z } from 'zod';

export const applyReferralCodeSchema = z.object({
  code: z.string().min(4).max(12).trim().toUpperCase(),
});
export type ApplyReferralCodeBody = z.infer<typeof applyReferralCodeSchema>;
