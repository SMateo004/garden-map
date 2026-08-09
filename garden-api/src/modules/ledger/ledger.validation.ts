import { z } from 'zod';

export const manualEntryLineSchema = z.object({
  accountCode: z.string().min(3).max(10),
  debit: z.coerce.number().min(0).default(0),
  credit: z.coerce.number().min(0).default(0),
});

export const createManualEntrySchema = z
  .object({
    date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'date formato YYYY-MM-DD'),
    description: z.string().min(3).max(300),
    lines: z.array(manualEntryLineSchema).min(2, 'Un asiento necesita al menos 2 líneas'),
  })
  .refine(
    (data) => {
      const totalDebit = Math.round(data.lines.reduce((s, l) => s + l.debit, 0) * 100);
      const totalCredit = Math.round(data.lines.reduce((s, l) => s + l.credit, 0) * 100);
      return totalDebit === totalCredit && totalDebit > 0;
    },
    { message: 'El total del Debe debe ser igual al total del Haber, y mayor a 0', path: ['lines'] }
  );
export type CreateManualEntryBody = z.infer<typeof createManualEntrySchema>;

export const monthParamsSchema = z.object({
  year: z.coerce.number().int().min(2020).max(2100),
  month: z.coerce.number().int().min(1).max(12),
});
