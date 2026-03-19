import { z } from 'zod';

export const reviewCaregiverBodySchema = z
  .object({
    action: z.enum(['approve', 'reject', 'request_revision', 'force_submit']),
    reason: z.string().max(2000).optional(),
    adminMessage: z.string().max(2000).optional(),
    checklist: z.array(z.string().max(200)).max(20).optional(),
    force: z.boolean().optional(),
  })
  .strict()
  .refine(
    (data) => data.action !== 'reject' || (data.reason != null && data.reason.trim().length > 0),
    { message: 'El motivo (reason) es obligatorio cuando la acción es reject', path: ['reason'] }
  )
  ;

export type ReviewCaregiverBody = z.infer<typeof reviewCaregiverBodySchema>;

export const pendingCaregiversQuerySchema = z.object({
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(20),
});

export type PendingCaregiversQuery = z.infer<typeof pendingCaregiversQuerySchema>;

/** Query para GET /api/admin/caregivers — lista todos con filtro opcional por estado. status=pendientes → PENDING_REVIEW + NEEDS_REVISION. */
export const listCaregiversQuerySchema = z.object({
  status: z
    .enum(['', 'pendientes', 'PENDING_REVIEW', 'NEEDS_REVISION', 'APPROVED', 'REJECTED', 'DRAFT', 'SUSPENDED'])
    .optional()
    .transform((v) => (v === '' ? undefined : v)),
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(20),
});

export type ListCaregiversQuery = z.infer<typeof listCaregiversQuerySchema>;

export const suspendCaregiverSchema = z.object({
  reason: z.string().min(5, 'El motivo debe tener al menos 5 caracteres').max(1000),
});

export type SuspendCaregiverBody = z.infer<typeof suspendCaregiverSchema>;

export const activateCaregiverSchema = z.object({
  notes: z.string().max(1000).optional(),
});

export type ActivateCaregiverBody = z.infer<typeof activateCaregiverSchema>;

export const deleteCaregiverSchema = z.object({
  reason: z.string().min(5, 'El motivo es obligatorio para eliminar').max(1000),
  adminPassword: z.string().min(1, 'La contraseña de admin es obligatoria'),
});

export type DeleteCaregiverBody = z.infer<typeof deleteCaregiverSchema>;
