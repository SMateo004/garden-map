/**
 * Distribución de la comisión de GARDEN (Admin > Comisiones > Distribución).
 *
 * La comisión cobrada (Booking.commissionAmount de reservas COMPLETED) se reparte en
 * destinos fijos — sueldos, mantenimiento, activos, fondo de garantía, otros gastos e
 * inversores — según un plan de porcentajes que suma 100.
 *
 * Reglas:
 *  - El plan es versionado (CommissionAllocationPlan, solo se agregan filas). Cada reserva
 *    se reparte con el plan vigente cuando terminó el servicio: cambiar los % hoy no
 *    reescribe lo que ya se asignó ayer.
 *  - Sin ningún plan guardado se usa DEFAULT_ALLOCATION (marcado isDefault en la respuesta).
 *  - Los montos se reparten al centavo con resto mayor: la suma de los destinos es
 *    exactamente la comisión, sin centavos que aparezcan o desaparezcan.
 *  - Lo que realmente se gastó de cada destino se registra como CommissionBucketMovement;
 *    disponible = asignado (histórico) − movimientos.
 *  - Fondo de garantía: cubre emergencias veterinarias de hasta guaranteeFundClaimCapBs
 *    (Bs 2.000) por caso — ver soporte-chat.agent.ts. Se informa cuántos casos cubre hoy.
 *
 * Es contabilidad de gestión: no mueve dinero de ninguna billetera ni toca User.balance.
 */
import prisma from '../../config/database.js';
import { getNumericSetting } from '../../utils/settings-cache.js';

export type BucketKey = 'SUELDOS' | 'MANTENIMIENTO' | 'ACTIVOS' | 'FONDO_GARANTIA' | 'OTROS' | 'INVERSORES';

export const BUCKETS: ReadonlyArray<{ key: BucketKey; label: string; description: string }> = [
  { key: 'SUELDOS', label: 'Sueldos', description: 'Equipo, soporte y fundadores' },
  { key: 'MANTENIMIENTO', label: 'Mantenimiento', description: 'Servidores, APIs, SMS, tiendas de apps' },
  { key: 'ACTIVOS', label: 'Activos', description: 'Equipos, desarrollo de producto, propiedad intelectual' },
  {
    key: 'FONDO_GARANTIA',
    label: 'Fondo de garantía',
    description: 'Emergencias veterinarias durante un servicio (hasta Bs 2.000 por caso)',
  },
  { key: 'OTROS', label: 'Otros gastos', description: 'Marketing, legal, contabilidad, imprevistos' },
  { key: 'INVERSORES', label: 'Inversores', description: 'Retorno y dividendos para inversores' },
];
export const BUCKET_KEYS: readonly BucketKey[] = BUCKETS.map((b) => b.key);

export type Allocation = Record<BucketKey, number>;

export const DEFAULT_ALLOCATION: Allocation = {
  SUELDOS: 35,
  MANTENIMIENTO: 15,
  ACTIVOS: 10,
  FONDO_GARANTIA: 15,
  OTROS: 10,
  INVERSORES: 15,
};

export const SETTING_FUND_CLAIM_CAP = 'guaranteeFundClaimCapBs';
export const SETTING_FUND_TARGET_CASES = 'guaranteeFundTargetCases';
export const DEFAULT_FUND_CLAIM_CAP_BS = 2000;
export const DEFAULT_FUND_TARGET_CASES = 3;

export interface PlanVersion {
  id: string | null;
  effectiveFrom: Date;
  allocation: Allocation;
  note: string | null;
  createdBy: string | null;
  isDefault: boolean;
}

// ─── Funciones puras ────────────────────────────────────────────────────────

/** Valida que estén los seis destinos, cada uno 0–100 con hasta 2 decimales, y que sumen 100. */
export function validateAllocation(raw: Record<string, unknown>): { ok: true; allocation: Allocation } | { ok: false; error: string } {
  const out = {} as Allocation;
  for (const key of BUCKET_KEYS) {
    const v = raw[key];
    if (typeof v !== 'number' || !Number.isFinite(v) || v < 0 || v > 100) {
      return { ok: false, error: `${key}: debe ser un porcentaje entre 0 y 100` };
    }
    if (Math.abs(v * 100 - Math.round(v * 100)) > 1e-6) {
      return { ok: false, error: `${key}: máximo 2 decimales` };
    }
    out[key] = v;
  }
  const extra = Object.keys(raw).filter((k) => !BUCKET_KEYS.includes(k as BucketKey));
  if (extra.length) return { ok: false, error: `Destinos desconocidos: ${extra.join(', ')}` };
  const sumCents = BUCKET_KEYS.reduce((s, k) => s + Math.round(out[k] * 100), 0);
  if (sumCents !== 10000) {
    return { ok: false, error: `Los porcentajes deben sumar 100 % (suman ${(sumCents / 100).toFixed(2)} %)` };
  }
  return { ok: true, allocation: out };
}

/**
 * Reparte `amount` (Bs) según `allocation` al centavo, con resto mayor: la suma de las
 * partes es exactamente `amount`. Montos negativos se reparten igual (con signo).
 */
export function splitAmount(amount: number, allocation: Allocation): Allocation {
  const totalCents = Math.round(amount * 100);
  const sign = totalCents < 0 ? -1 : 1;
  const abs = Math.abs(totalCents);
  const raw = BUCKET_KEYS.map((k) => ({ k, exact: (abs * allocation[k]) / 100 }));
  const floors = raw.map((r) => ({ k: r.k, cents: Math.floor(r.exact + 1e-9), rem: r.exact - Math.floor(r.exact + 1e-9) }));
  let left = abs - floors.reduce((s, f) => s + f.cents, 0);
  // Desempate estable por orden de BUCKETS para que el resultado sea determinista.
  const order = [...floors].sort((a, b) => b.rem - a.rem || BUCKET_KEYS.indexOf(a.k) - BUCKET_KEYS.indexOf(b.k));
  for (const f of order) {
    if (left <= 0) break;
    if (allocation[f.k] <= 0) continue;
    f.cents += 1;
    left -= 1;
  }
  const out = {} as Allocation;
  for (const f of floors) out[f.k] = (sign * f.cents) / 100;
  return out;
}

export function emptyAllocation(): Allocation {
  return { SUELDOS: 0, MANTENIMIENTO: 0, ACTIVOS: 0, FONDO_GARANTIA: 0, OTROS: 0, INVERSORES: 0 };
}

export function addAllocations(a: Allocation, b: Allocation): Allocation {
  const out = emptyAllocation();
  for (const k of BUCKET_KEYS) out[k] = Math.round((a[k] + b[k]) * 100) / 100;
  return out;
}

/**
 * Tramos de [from, to) cubiertos por cada versión del plan. `plans` ordenados por
 * effectiveFrom ascendente; antes del primer plan rige el primero (o el default si no hay).
 */
export function planSegments(plans: PlanVersion[], from: Date, to: Date): Array<{ plan: PlanVersion; from: Date; to: Date }> {
  if (from >= to) return [];
  const list = plans.length ? plans : [defaultPlan()];
  const segments: Array<{ plan: PlanVersion; from: Date; to: Date }> = [];
  list.forEach((plan, i) => {
    const next = list[i + 1];
    const start = i === 0 ? new Date(-8.64e15) : plan.effectiveFrom;
    const end = next ? next.effectiveFrom : new Date(8.64e15);
    const s = start > from ? start : from;
    const e = end < to ? end : to;
    if (s < e) segments.push({ plan, from: s, to: e });
  });
  return segments;
}

export function defaultPlan(): PlanVersion {
  return {
    id: null,
    effectiveFrom: new Date(0),
    allocation: { ...DEFAULT_ALLOCATION },
    note: null,
    createdBy: null,
    isDefault: true,
  };
}

// ─── Acceso a datos ─────────────────────────────────────────────────────────

function parseStoredAllocation(json: unknown): Allocation | null {
  if (!json || typeof json !== 'object') return null;
  const asRecord: Record<string, unknown> = {};
  if (Array.isArray(json)) {
    for (const item of json as Array<{ key?: unknown; pct?: unknown }>) {
      if (typeof item?.key === 'string') asRecord[item.key] = Number(item.pct);
    }
  } else {
    Object.assign(asRecord, json);
  }
  const r = validateAllocation(asRecord);
  return r.ok ? r.allocation : null;
}

export async function loadPlans(): Promise<PlanVersion[]> {
  const rows = await prisma.commissionAllocationPlan.findMany({ orderBy: { effectiveFrom: 'asc' } });
  const plans: PlanVersion[] = [];
  for (const r of rows) {
    const allocation = parseStoredAllocation(r.buckets);
    if (!allocation) continue; // fila corrupta: se ignora en vez de romper el reporte
    plans.push({
      id: r.id,
      effectiveFrom: r.effectiveFrom,
      allocation,
      note: r.note,
      createdBy: r.createdBy,
      isDefault: false,
    });
  }
  return plans;
}

export async function savePlan(allocation: Allocation, note: string | null, adminId: string | undefined): Promise<PlanVersion> {
  const row = await prisma.commissionAllocationPlan.create({
    data: {
      buckets: BUCKET_KEYS.map((key) => ({ key, pct: allocation[key] })),
      note,
      createdBy: adminId ?? null,
    },
  });
  return { id: row.id, effectiveFrom: row.effectiveFrom, allocation, note: row.note, createdBy: row.createdBy, isDefault: false };
}

/** Comisión cobrada en [from, to): reservas COMPLETED por fecha de fin de servicio. */
async function commissionBetween(from: Date, to: Date): Promise<number> {
  const agg = await prisma.booking.aggregate({
    where: {
      status: 'COMPLETED',
      OR: [
        { serviceEndedAt: { gte: from, lt: to } },
        // Reservas viejas completadas sin serviceEndedAt: se fechan por su última actualización.
        { serviceEndedAt: null, updatedAt: { gte: from, lt: to } },
      ],
    },
    _sum: { commissionAmount: true },
  });
  return Number(agg._sum.commissionAmount ?? 0);
}

/** Comisión de [from, to) repartida con el plan vigente en cada tramo. */
export async function allocateBetween(plans: PlanVersion[], from: Date, to: Date): Promise<{ commission: number; allocated: Allocation }> {
  let commission = 0;
  let allocated = emptyAllocation();
  for (const seg of planSegments(plans, from, to)) {
    const c = await commissionBetween(seg.from, seg.to);
    if (c === 0) continue;
    commission += c;
    allocated = addAllocations(allocated, splitAmount(c, seg.plan.allocation));
  }
  return { commission: Math.round(commission * 100) / 100, allocated };
}

async function spentBetween(from: Date, to: Date): Promise<Allocation> {
  const rows = await prisma.commissionBucketMovement.groupBy({
    by: ['bucket'],
    where: { occurredAt: { gte: from, lt: to } },
    _sum: { amount: true },
  });
  const out = emptyAllocation();
  for (const r of rows) {
    if (BUCKET_KEYS.includes(r.bucket as BucketKey)) out[r.bucket as BucketKey] = Number(r._sum.amount ?? 0);
  }
  return out;
}

export type AllocationPeriod = 'month' | 'year' | 'all';

function periodStart(period: AllocationPeriod, now: Date): Date {
  if (period === 'month') return new Date(now.getFullYear(), now.getMonth(), 1);
  if (period === 'year') return new Date(now.getFullYear(), 0, 1);
  return new Date(0);
}

export async function getAllocationReport(period: AllocationPeriod) {
  const now = new Date();
  const farFuture = new Date(now.getTime() + 24 * 3600 * 1000);
  const from = periodStart(period, now);
  const plans = await loadPlans();
  const current = plans[plans.length - 1] ?? defaultPlan();

  const [periodAlloc, allTimeAlloc, spentPeriod, spentAll, capRaw, targetRaw, movements] = await Promise.all([
    allocateBetween(plans, from, farFuture),
    period === 'all' ? null : allocateBetween(plans, new Date(0), farFuture),
    spentBetween(from, farFuture),
    period === 'all' ? null : spentBetween(new Date(0), farFuture),
    getNumericSetting(SETTING_FUND_CLAIM_CAP, DEFAULT_FUND_CLAIM_CAP_BS),
    getNumericSetting(SETTING_FUND_TARGET_CASES, DEFAULT_FUND_TARGET_CASES),
    prisma.commissionBucketMovement.findMany({ orderBy: { occurredAt: 'desc' }, take: 50 }),
  ]);
  const allTime = allTimeAlloc ?? periodAlloc;
  const spentAllTime = spentAll ?? spentPeriod;

  const buckets = BUCKETS.map((b) => {
    const allocatedAllTime = allTime.allocated[b.key];
    const spent = spentAllTime[b.key];
    return {
      key: b.key,
      label: b.label,
      description: b.description,
      pct: current.allocation[b.key],
      allocatedPeriod: periodAlloc.allocated[b.key],
      spentPeriod: spentPeriod[b.key],
      allocatedAllTime,
      spentAllTime: spent,
      available: Math.round((allocatedAllTime - spent) * 100) / 100,
    };
  });

  const claimCapBs = capRaw > 0 ? capRaw : DEFAULT_FUND_CLAIM_CAP_BS;
  const targetCases = targetRaw >= 1 ? Math.floor(targetRaw) : DEFAULT_FUND_TARGET_CASES;
  const fundAvailable = buckets.find((b) => b.key === 'FONDO_GARANTIA')!.available;
  const targetAmount = claimCapBs * targetCases;

  // Últimos 6 meses, repartidos con el plan de cada tramo.
  const monthly: Array<{ month: string; commission: number; allocated: Allocation }> = [];
  for (let i = 5; i >= 0; i--) {
    const mStart = new Date(now.getFullYear(), now.getMonth() - i, 1);
    const mEnd = new Date(now.getFullYear(), now.getMonth() - i + 1, 1);
    const m = await allocateBetween(plans, mStart, mEnd);
    monthly.push({ month: mStart.toLocaleString('es', { month: 'short', year: '2-digit' }), ...m });
  }

  return {
    period,
    from: from.toISOString(),
    commissionCollectedPeriod: periodAlloc.commission,
    commissionCollectedAllTime: allTime.commission,
    plan: {
      id: current.id,
      effectiveFrom: current.effectiveFrom.toISOString(),
      isDefault: current.isDefault,
      note: current.note,
    },
    history: plans
      .slice()
      .reverse()
      .slice(0, 20)
      .map((p) => ({ id: p.id, effectiveFrom: p.effectiveFrom.toISOString(), allocation: p.allocation, note: p.note })),
    buckets,
    fund: {
      available: fundAvailable,
      claimCapBs,
      targetCases,
      targetAmount,
      casesCovered: fundAvailable > 0 ? Math.floor(fundAvailable / claimCapBs) : 0,
      progressPct: targetAmount > 0 ? Math.max(0, Math.min(100, (fundAvailable / targetAmount) * 100)) : 0,
    },
    monthly,
    movements: movements.map((m) => ({
      id: m.id,
      bucket: m.bucket,
      amount: Number(m.amount),
      description: m.description,
      occurredAt: m.occurredAt.toISOString(),
      bookingId: m.bookingId,
    })),
  };
}
