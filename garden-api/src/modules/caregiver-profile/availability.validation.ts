import { z } from 'zod';

const dateStrSchema = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Formato YYYY-MM-DD');

const timeBlocksSchema = z
  .object({
    MANANA: z.boolean().optional(),
    TARDE: z.boolean().optional(),
    NOCHE: z.boolean().optional(),
  })
  .optional();

export const defaultScheduleSchema = z
  .object({
    hospedajeDefault: z.boolean().optional(),
    paseoTimeBlocks: timeBlocksSchema,
    weekdays: z.boolean().optional(),
    weekends: z.boolean().optional(),
    holidays: z.boolean().optional(),
  })
  .optional();

export const dayOverrideSchema = z.object({
  isAvailable: z.boolean().optional(),
  timeBlocks: timeBlocksSchema,
});

export const patchAvailabilityBodySchema = z.object({
  defaultSchedule: defaultScheduleSchema,
  overrides: z.record(dateStrSchema, dayOverrideSchema).optional(),
});

export type PatchAvailabilityBody = z.infer<typeof patchAvailabilityBodySchema>;
export type DefaultSchedule = z.infer<typeof defaultScheduleSchema>;
