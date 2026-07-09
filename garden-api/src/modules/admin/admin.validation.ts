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

/** Schema para solicitar revisión de perfil aprobado por actividad sospechosa */
export const flagReviewSchema = z.object({
  reason: z.string().min(5, 'El motivo debe tener al menos 5 caracteres').max(1000).default('Actividad sospechosa detectada'),
});

export type FlagReviewBody = z.infer<typeof flagReviewSchema>;

export const deleteCaregiverSchema = z.object({
  reason: z.string().min(5, 'El motivo es obligatorio para eliminar').max(1000),
  adminPassword: z.string().min(1, 'La contraseña de admin es obligatoria'),
});

export type DeleteCaregiverBody = z.infer<typeof deleteCaregiverSchema>;

// ── Gift codes ────────────────────────────────────────────────────────────────
export const createGiftCodeSchema = z.object({
  code: z.string().min(3, 'El código debe tener al menos 3 caracteres').max(32).regex(/^[A-Z0-9_-]+$/i, 'El código solo puede contener letras, números, guiones y guiones bajos'),
  amount: z.number().int().min(1, 'El monto debe ser al menos 1').max(10000, 'El monto no puede exceder 10,000'),
  maxUses: z.number().int().min(1).max(10000).optional(),
  expiresAt: z.string().datetime({ offset: true }).optional().nullable(),
});

export type CreateGiftCodeBody = z.infer<typeof createGiftCodeSchema>;

// ── Withdrawals ───────────────────────────────────────────────────────────────
export const rejectWithdrawalSchema = z.object({
  reason: z.string().max(500).optional(),
});

export type RejectWithdrawalBody = z.infer<typeof rejectWithdrawalSchema>;

// ── Settings — only allow explicitly named keys ───────────────────────────────
export const ALLOWED_SETTING_KEYS = [
  // Feature flags (boolean)
  'marketplaceEnabled',
  'paymentsEnabled',
  'newRegistrationsEnabled',
  'walk30Enabled',
  'maintenanceMode',
  'hospedajeEnabled',
  'paseoEnabled',
  'guarderiaEnabled',
  'retirosEnabled',
  'disputasEnabled',
  'preciosDinamicosEnabled',
  'meetGreetEnabled',
  'otpVisibleToAdminEnabled',
  // Beta access control
  'betaInviteRequired',
  'betaInviteCodes',
  // Pagos y finanzas (numeric)
  'platformCommissionPct',
  'montoMinimoRetiro',
  'qrValidityMinutes',
  'autoReleasePaymentHoras',
  'onHoldSlaHoras',
  // Política cancelación HOSPEDAJE (numeric)
  'hospedajeRefundAdminFeeBS',
  'hospedajeRefund100Horas',
  'hospedajeRefund50Horas',
  // Política cancelación PASEO (numeric)
  'paseoRefund100Horas',
  'paseoRefund50Horas',
  // Límites de precio por tipo de servicio (numeric)
  'paseoMinPrice',
  'paseoMaxPrice',
  'hospedajeMinPrice',
  'hospedajeMaxPrice',
  'guarderiaMinPrice',
  'guarderiaMaxPrice',
  // Zonas bloqueadas (JSON array)
  'blockedZones',
  // Registro profesional y empresas
  'professionalRegistrationCode',
  'companyRegistrationCode',
  // Versión mínima de app (force-update)
  'minAppVersion',
  'storeUrlIos',
  'storeUrlAndroid',
  'forceUpdateEnabled',
] as const;

export type AllowedSettingKey = typeof ALLOWED_SETTING_KEYS[number];

// ── Admin notifications ───────────────────────────────────────────────────────
export const sendAdminNotificationSchema = z.object({
  title: z.string().min(1).max(100),
  message: z.string().min(1).max(1000),
  target: z.enum(['TODOS', 'CUIDADORES', 'DUENOS']),
  type: z.string().max(50).optional().default('SYSTEM'),
});

export const scheduleAdminNotificationSchema = sendAdminNotificationSchema.extend({
  scheduledAt: z.string().datetime({ offset: true }),
});

export type SendAdminNotificationBody = z.infer<typeof sendAdminNotificationSchema>;
export type ScheduleAdminNotificationBody = z.infer<typeof scheduleAdminNotificationSchema>;

// ── Agent instruction ─────────────────────────────────────────────────────────
export const postAgentInstructionSchema = z.object({
  agentType: z.enum(['REPUTACION', 'PRECIOS', 'MONITOR', 'CUSTOM']).default('CUSTOM'),
  action: z.string().min(1).max(100).optional(),
  // input is freeform JSON (object or null); validated at runtime by Prisma
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  input: z.any().optional().nullable(),
});

export type PostAgentInstructionBody = z.infer<typeof postAgentInstructionSchema>;
