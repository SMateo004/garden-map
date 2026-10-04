/**
 * Admin > Comisiones e impuestos.
 *
 *   GET    /api/admin/pricing                  configuración completa (global + por servicio + overrides)
 *   PUT    /api/admin/pricing/global           comisión por defecto, impuesto y comisión por servicio
 *   PUT    /api/admin/pricing/overrides        crea/actualiza la comisión de un cuidador/empresa
 *   DELETE /api/admin/pricing/overrides/:id    quita un override (vuelve a la comisión del servicio)
 *   GET    /api/admin/pricing/caregivers?q=    buscador de cuidadores/empresas para asignar un override
 *   POST   /api/admin/pricing/preview          simula cuánto paga el cliente por un precio de cuidador
 *
 *   GET    /api/admin/pricing/allocation?period=month|year|all   a dónde va la comisión (reporte)
 *   PUT    /api/admin/pricing/allocation                         nueva versión del plan de distribución
 *   POST   /api/admin/pricing/allocation/movements               registra un gasto real de un destino
 *   DELETE /api/admin/pricing/allocation/movements/:id           anula un gasto mal cargado
 *
 * Solo toca AppSettings (global) y CaregiverCommissionOverride; las reservas ya creadas
 * conservan los montos con los que se crearon (commissionAmount / taxAmount).
 */
import { Router, Request, Response } from 'express';
import { z } from 'zod';
import prisma from '../../config/database.js';
import { asyncHandler } from '../../shared/async-handler.js';
import { BadRequestError, NotFoundError } from '../../shared/errors.js';
import { auditLog } from '../../services/audit.service.js';
import { delByPrefix } from '../../shared/cache.js';
import logger from '../../shared/logger.js';
import { invalidateSetting } from '../../utils/settings-cache.js';
import {
  MAX_COMMISSION_PCT,
  MAX_TAX_RATE_PCT,
  PRICED_SERVICES,
  SETTING_DEFAULT_COMMISSION,
  SETTING_SERVICE_COMMISSION,
  SETTING_TAX_RATE,
  computeClientCharge,
  getPricingConfig,
  invalidatePricingConfig,
  resolveCommissionPct,
  type PricedService,
} from './pricing.service.js';
import {
  BUCKET_KEYS,
  SETTING_FUND_CLAIM_CAP,
  SETTING_FUND_TARGET_CASES,
  getAllocationReport,
  loadPlans,
  savePlan,
  validateAllocation,
  type AllocationPeriod,
} from './commission-allocation.service.js';

const pct = (max: number) => z.number().min(0).max(max).multipleOf(0.01);

const globalBodySchema = z.object({
  defaultCommissionPct: pct(MAX_COMMISSION_PCT),
  taxRatePct: pct(MAX_TAX_RATE_PCT),
  /** null = sin comisión propia (usa la por defecto). */
  services: z.object({
    PASEO: pct(MAX_COMMISSION_PCT).nullable(),
    GUARDERIA: pct(MAX_COMMISSION_PCT).nullable(),
    HOSPEDAJE: pct(MAX_COMMISSION_PCT).nullable(),
  }),
});

const overrideBodySchema = z.object({
  caregiverId: z.string().uuid(),
  serviceType: z.enum(['ALL', 'PASEO', 'GUARDERIA', 'HOSPEDAJE']),
  pct: pct(MAX_COMMISSION_PCT),
});

const previewBodySchema = z.object({
  serviceType: z.enum(['PASEO', 'GUARDERIA', 'HOSPEDAJE']),
  caregiverId: z.string().uuid().optional(),
  caregiverPrice: z.number().min(1).max(100000),
});

/** Los listados/perfiles de cuidadores cachean el precio con comisión: se invalidan al cambiar tarifas. */
async function invalidateCaregiverCaches(): Promise<void> {
  invalidatePricingConfig();
  try {
    await delByPrefix('caregivers:');
  } catch (err) {
    logger.warn('[PRICING] no se pudo invalidar el cache de cuidadores', { err });
  }
}

async function writeSetting(key: string, value: number | null, adminId: string | undefined): Promise<void> {
  if (value === null) {
    await prisma.appSettings.deleteMany({ where: { key } });
    return;
  }
  await prisma.appSettings.upsert({
    where: { key },
    update: { value: JSON.stringify(value), updatedBy: adminId },
    create: { key, value: JSON.stringify(value), updatedBy: adminId },
  });
}

async function buildConfigResponse() {
  const cfg = await getPricingConfig();
  const rows = await prisma.caregiverCommissionOverride.findMany({
    orderBy: [{ updatedAt: 'desc' }],
    include: {
      caregiver: {
        select: {
          id: true,
          isCompany: true,
          companyName: true,
          user: { select: { firstName: true, lastName: true } },
        },
      },
    },
  });
  return {
    defaultCommissionPct: cfg.defaultCommissionPct,
    taxRatePct: cfg.taxRatePct,
    services: Object.fromEntries(
      PRICED_SERVICES.map((svc) => [
        svc,
        { explicitPct: cfg.serviceCommissionPct[svc] ?? null, effectivePct: resolveCommissionPct(cfg, svc, null) },
      ])
    ),
    overrides: rows.map((r) => ({
      id: r.id,
      caregiverId: r.caregiverId,
      caregiverName: `${r.caregiver.user.firstName} ${r.caregiver.user.lastName}`.trim(),
      isCompany: r.caregiver.isCompany,
      companyName: r.caregiver.companyName,
      serviceType: r.serviceType,
      pct: Number(r.pct),
      updatedAt: r.updatedAt.toISOString(),
    })),
    limits: { maxCommissionPct: MAX_COMMISSION_PCT, maxTaxRatePct: MAX_TAX_RATE_PCT },
  };
}

const router = Router();

router.get(
  '/',
  asyncHandler(async (_req: Request, res: Response) => {
    res.json({ success: true, data: await buildConfigResponse() });
  })
);

router.put(
  '/global',
  asyncHandler(async (req: Request, res: Response) => {
    const body = globalBodySchema.parse(req.body);
    const adminId = req.user?.userId;
    const before = await getPricingConfig();

    await writeSetting(SETTING_DEFAULT_COMMISSION, body.defaultCommissionPct, adminId);
    await writeSetting(SETTING_TAX_RATE, body.taxRatePct, adminId);
    for (const svc of PRICED_SERVICES) {
      await writeSetting(SETTING_SERVICE_COMMISSION[svc], body.services[svc], adminId);
    }
    await invalidateCaregiverCaches();

    auditLog({
      userId: adminId,
      action: 'PRICING_GLOBAL_UPDATED',
      entity: 'AppSettings',
      details: {
        before: {
          defaultCommissionPct: before.defaultCommissionPct,
          taxRatePct: before.taxRatePct,
          services: before.serviceCommissionPct,
        },
        after: body,
      },
      ip: req.ip,
    });
    res.json({ success: true, data: await buildConfigResponse() });
  })
);

router.put(
  '/overrides',
  asyncHandler(async (req: Request, res: Response) => {
    const body = overrideBodySchema.parse(req.body);
    const adminId = req.user?.userId;

    const profile = await prisma.caregiverProfile.findUnique({
      where: { id: body.caregiverId },
      select: { id: true },
    });
    if (!profile) throw new NotFoundError('Cuidador o empresa no encontrado');

    const saved = await prisma.caregiverCommissionOverride.upsert({
      where: { caregiverId_serviceType: { caregiverId: body.caregiverId, serviceType: body.serviceType } },
      update: { pct: body.pct, updatedBy: adminId },
      create: { caregiverId: body.caregiverId, serviceType: body.serviceType, pct: body.pct, updatedBy: adminId },
    });
    await invalidateCaregiverCaches();

    auditLog({
      userId: adminId,
      action: 'PRICING_OVERRIDE_SET',
      entity: 'CaregiverProfile',
      entityId: body.caregiverId,
      details: { serviceType: body.serviceType, pct: body.pct },
      ip: req.ip,
    });
    res.json({ success: true, data: { id: saved.id, config: await buildConfigResponse() } });
  })
);

router.delete(
  '/overrides/:id',
  asyncHandler(async (req: Request, res: Response) => {
    const id = String(req.params.id);
    const existing = await prisma.caregiverCommissionOverride.findUnique({ where: { id } });
    if (!existing) throw new NotFoundError('Comisión personalizada no encontrada');
    await prisma.caregiverCommissionOverride.delete({ where: { id } });
    await invalidateCaregiverCaches();
    auditLog({
      userId: req.user?.userId,
      action: 'PRICING_OVERRIDE_REMOVED',
      entity: 'CaregiverProfile',
      entityId: existing.caregiverId,
      details: { serviceType: existing.serviceType, pct: Number(existing.pct) },
      ip: req.ip,
    });
    res.json({ success: true, data: await buildConfigResponse() });
  })
);

/** Buscador para elegir a quién personalizar: por nombre de persona/empresa. Empresas primero. */
router.get(
  '/caregivers',
  asyncHandler(async (req: Request, res: Response) => {
    const q = String(req.query.q ?? '').trim();
    const companiesOnly = String(req.query.companiesOnly ?? 'false') === 'true';
    if (q.length > 80) throw new BadRequestError('Búsqueda demasiado larga');
    const rows = await prisma.caregiverProfile.findMany({
      where: {
        ...(companiesOnly ? { isCompany: true } : {}),
        ...(q
          ? {
              OR: [
                { companyName: { contains: q, mode: 'insensitive' } },
                { user: { firstName: { contains: q, mode: 'insensitive' } } },
                { user: { lastName: { contains: q, mode: 'insensitive' } } },
              ],
            }
          : {}),
      },
      select: {
        id: true,
        isCompany: true,
        companyName: true,
        user: { select: { firstName: true, lastName: true } },
      },
      orderBy: [{ isCompany: 'desc' }, { createdAt: 'desc' }],
      take: 20,
    });
    res.json({
      success: true,
      data: rows.map((r) => ({
        id: r.id,
        name: `${r.user.firstName} ${r.user.lastName}`.trim(),
        isCompany: r.isCompany,
        companyName: r.companyName,
      })),
    });
  })
);

router.post(
  '/preview',
  asyncHandler(async (req: Request, res: Response) => {
    const body = previewBodySchema.parse(req.body);
    const cfg = await getPricingConfig();
    const commissionPct = resolveCommissionPct(cfg, body.serviceType, body.caregiverId ?? null);
    const charge = computeClientCharge(body.caregiverPrice, commissionPct / 100, cfg.taxRatePct / 100);
    res.json({
      success: true,
      data: {
        serviceType: body.serviceType as PricedService,
        commissionPct,
        taxRatePct: cfg.taxRatePct,
        caregiverPrice: charge.base,
        commission: charge.commission,
        priceBeforeTax: charge.priced,
        tax: charge.tax,
        clientPays: charge.total,
      },
    });
  })
);

// ─── Distribución de la comisión ─────────────────────────────────────────────

const allocationBodySchema = z.object({
  allocation: z.record(z.number()),
  note: z.string().trim().max(300).optional(),
  fundClaimCapBs: z.number().int().min(100).max(100000).optional(),
  fundTargetCases: z.number().int().min(1).max(100).optional(),
});

const movementBodySchema = z.object({
  bucket: z.enum(BUCKET_KEYS as [string, ...string[]]),
  amount: z
    .number()
    .multipleOf(0.01)
    .refine((v) => v !== 0 && Math.abs(v) <= 1_000_000, 'Monto inválido (distinto de 0, hasta Bs 1.000.000)'),
  description: z.string().trim().min(3).max(300),
  occurredAt: z.string().datetime().optional(),
  bookingId: z.string().uuid().optional(),
});

router.get(
  '/allocation',
  asyncHandler(async (req: Request, res: Response) => {
    const raw = String(req.query.period ?? 'month');
    const period: AllocationPeriod = raw === 'year' || raw === 'all' ? raw : 'month';
    res.json({ success: true, data: await getAllocationReport(period) });
  })
);

router.put(
  '/allocation',
  asyncHandler(async (req: Request, res: Response) => {
    const body = allocationBodySchema.parse(req.body);
    const checked = validateAllocation(body.allocation);
    if (!checked.ok) throw new BadRequestError(checked.error);
    const adminId = req.user?.userId;

    const plans = await loadPlans();
    const before = plans[plans.length - 1]?.allocation ?? null;
    const changed = !before || BUCKET_KEYS.some((k) => before[k] !== checked.allocation[k]);
    // Guardar el mismo plan otra vez no crea una versión nueva (el historial queda limpio).
    if (changed) await savePlan(checked.allocation, body.note || null, adminId);
    if (body.fundClaimCapBs !== undefined) await writeSetting(SETTING_FUND_CLAIM_CAP, body.fundClaimCapBs, adminId);
    if (body.fundTargetCases !== undefined) await writeSetting(SETTING_FUND_TARGET_CASES, body.fundTargetCases, adminId);
    invalidateSetting(SETTING_FUND_CLAIM_CAP);
    invalidateSetting(SETTING_FUND_TARGET_CASES);

    auditLog({
      userId: adminId,
      action: 'COMMISSION_ALLOCATION_UPDATED',
      entity: 'CommissionAllocationPlan',
      details: {
        before,
        after: checked.allocation,
        newVersion: changed,
        fundClaimCapBs: body.fundClaimCapBs,
        fundTargetCases: body.fundTargetCases,
      },
      ip: req.ip,
    });
    res.json({ success: true, data: await getAllocationReport('month') });
  })
);

router.post(
  '/allocation/movements',
  asyncHandler(async (req: Request, res: Response) => {
    const body = movementBodySchema.parse(req.body);
    const occurredAt = body.occurredAt ? new Date(body.occurredAt) : new Date();
    if (occurredAt.getTime() > Date.now() + 24 * 3600 * 1000) {
      throw new BadRequestError('La fecha del gasto no puede ser futura');
    }
    if (body.bookingId) {
      const exists = await prisma.booking.findUnique({ where: { id: body.bookingId }, select: { id: true } });
      if (!exists) throw new NotFoundError('Reserva no encontrada');
    }
    const adminId = req.user?.userId;
    const saved = await prisma.commissionBucketMovement.create({
      data: {
        bucket: body.bucket,
        amount: body.amount,
        description: body.description,
        occurredAt,
        bookingId: body.bookingId ?? null,
        createdBy: adminId ?? null,
      },
    });
    auditLog({
      userId: adminId,
      action: 'COMMISSION_BUCKET_MOVEMENT_CREATED',
      entity: 'CommissionBucketMovement',
      entityId: saved.id,
      details: { bucket: body.bucket, amount: body.amount, description: body.description, bookingId: body.bookingId },
      ip: req.ip,
    });
    res.json({ success: true, data: { id: saved.id } });
  })
);

router.delete(
  '/allocation/movements/:id',
  asyncHandler(async (req: Request, res: Response) => {
    const id = String(req.params.id);
    const existing = await prisma.commissionBucketMovement.findUnique({ where: { id } });
    if (!existing) throw new NotFoundError('Movimiento no encontrado');
    await prisma.commissionBucketMovement.delete({ where: { id } });
    // El registro completo queda en la auditoría.
    auditLog({
      userId: req.user?.userId,
      action: 'COMMISSION_BUCKET_MOVEMENT_REMOVED',
      entity: 'CommissionBucketMovement',
      entityId: id,
      details: {
        bucket: existing.bucket,
        amount: Number(existing.amount),
        description: existing.description,
        occurredAt: existing.occurredAt.toISOString(),
        bookingId: existing.bookingId,
      },
      ip: req.ip,
    });
    res.json({ success: true });
  })
);

export default router;
