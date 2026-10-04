/**
 * Distribución de la comisión (commission-allocation.service.ts).
 * Invariantes que no pueden romperse:
 *   - los destinos suman exactamente la comisión (ni un centavo de más o de menos);
 *   - un plan debe sumar 100 % y cubrir los seis destinos;
 *   - cambiar el plan no reescribe lo asignado antes del cambio.
 */
import {
  BUCKET_KEYS,
  DEFAULT_ALLOCATION,
  allocateBetween,
  getAllocationReport,
  planSegments,
  splitAmount,
  validateAllocation,
  type Allocation,
  type PlanVersion,
} from '../../src/modules/pricing/commission-allocation.service';
import { ALLOWED_SETTING_KEYS } from '../../src/modules/admin/admin.validation';
import prisma from '../../src/config/database';

jest.mock('../../src/config/database', () => ({
  __esModule: true,
  default: {
    booking: { aggregate: jest.fn() },
    commissionAllocationPlan: { findMany: jest.fn().mockResolvedValue([]) },
    commissionBucketMovement: {
      groupBy: jest.fn().mockResolvedValue([]),
      findMany: jest.fn().mockResolvedValue([]),
    },
    appSettings: { findUnique: jest.fn().mockResolvedValue(null) },
  },
}));

const mockPrisma = prisma as unknown as {
  booking: { aggregate: jest.Mock };
  commissionAllocationPlan: { findMany: jest.Mock };
  commissionBucketMovement: { groupBy: jest.Mock; findMany: jest.Mock };
};

const sum = (a: Allocation) => Math.round(BUCKET_KEYS.reduce((s, k) => s + a[k] * 100, 0)) / 100;

function plan(effectiveFrom: string, allocation: Allocation): PlanVersion {
  return { id: effectiveFrom, effectiveFrom: new Date(effectiveFrom), allocation, note: null, createdBy: null, isDefault: false };
}

const ALL_TO_INVESTORS: Allocation = { SUELDOS: 0, MANTENIMIENTO: 0, ACTIVOS: 0, FONDO_GARANTIA: 0, OTROS: 0, INVERSORES: 100 };

describe('validateAllocation', () => {
  it('acepta el plan por defecto (suma 100)', () => {
    expect(validateAllocation({ ...DEFAULT_ALLOCATION })).toEqual({ ok: true, allocation: DEFAULT_ALLOCATION });
  });

  it('rechaza si no suma 100 y dice cuánto suma', () => {
    const r = validateAllocation({ ...DEFAULT_ALLOCATION, INVERSORES: 20 });
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error).toContain('105.00');
  });

  it('acepta decimales que suman 100 exacto (sin error de coma flotante)', () => {
    const r = validateAllocation({ SUELDOS: 33.33, MANTENIMIENTO: 33.33, ACTIVOS: 33.34, FONDO_GARANTIA: 0, OTROS: 0, INVERSORES: 0 });
    expect(r.ok).toBe(true);
  });

  it('rechaza destinos faltantes, desconocidos, negativos o con más de 2 decimales', () => {
    const { INVERSORES: _omit, ...missing } = DEFAULT_ALLOCATION;
    expect(validateAllocation(missing).ok).toBe(false);
    expect(validateAllocation({ ...DEFAULT_ALLOCATION, MARKETING: 0 }).ok).toBe(false);
    expect(validateAllocation({ ...DEFAULT_ALLOCATION, SUELDOS: -5, INVERSORES: 55 }).ok).toBe(false);
    expect(validateAllocation({ ...DEFAULT_ALLOCATION, SUELDOS: 34.999, INVERSORES: 15.001 }).ok).toBe(false);
  });
});

describe('splitAmount', () => {
  it('reparte según los porcentajes', () => {
    expect(splitAmount(1000, DEFAULT_ALLOCATION)).toEqual({
      SUELDOS: 350, MANTENIMIENTO: 150, ACTIVOS: 100, FONDO_GARANTIA: 150, OTROS: 100, INVERSORES: 150,
    });
  });

  it('la suma de los destinos es exactamente el monto (montos aleatorios y planes con tercios)', () => {
    const thirds: Allocation = { SUELDOS: 33.33, MANTENIMIENTO: 33.33, ACTIVOS: 33.34, FONDO_GARANTIA: 0, OTROS: 0, INVERSORES: 0 };
    for (let i = 0; i < 500; i++) {
      const amount = Math.round(Math.random() * 1_000_000) / 100;
      expect(sum(splitAmount(amount, DEFAULT_ALLOCATION))).toBe(amount);
      expect(sum(splitAmount(amount, thirds))).toBe(amount);
    }
  });

  it('nunca asigna centavos a un destino con 0 %', () => {
    const r = splitAmount(0.07, { SUELDOS: 50, MANTENIMIENTO: 0, ACTIVOS: 0, FONDO_GARANTIA: 50, OTROS: 0, INVERSORES: 0 });
    expect(r.MANTENIMIENTO).toBe(0);
    expect(r.SUELDOS + r.FONDO_GARANTIA).toBeCloseTo(0.07, 10);
  });

  it('montos negativos (ajustes) se reparten con signo', () => {
    expect(sum(splitAmount(-12.34, DEFAULT_ALLOCATION))).toBe(-12.34);
  });
});

describe('planSegments', () => {
  const plans = [plan('2026-03-01T00:00:00Z', DEFAULT_ALLOCATION), plan('2026-06-01T00:00:00Z', ALL_TO_INVESTORS)];

  it('corta el rango donde cambia el plan', () => {
    const segs = planSegments(plans, new Date('2026-05-01T00:00:00Z'), new Date('2026-07-01T00:00:00Z'));
    expect(segs).toHaveLength(2);
    expect(segs[0]!.plan.allocation).toBe(DEFAULT_ALLOCATION);
    expect(segs[0]!.to.toISOString()).toBe('2026-06-01T00:00:00.000Z');
    expect(segs[1]!.plan.allocation).toBe(ALL_TO_INVESTORS);
  });

  it('antes del primer plan rige el primero; sin planes rige el default', () => {
    const early = planSegments(plans, new Date('2025-01-01T00:00:00Z'), new Date('2025-02-01T00:00:00Z'));
    expect(early).toHaveLength(1);
    expect(early[0]!.plan.allocation).toBe(DEFAULT_ALLOCATION);
    const none = planSegments([], new Date('2025-01-01T00:00:00Z'), new Date('2025-02-01T00:00:00Z'));
    expect(none[0]!.plan.isDefault).toBe(true);
  });
});

describe('allocateBetween', () => {
  beforeEach(() => mockPrisma.booking.aggregate.mockReset());

  it('cambiar el plan no reescribe lo asignado antes del cambio', async () => {
    // Bs 1000 de comisión antes del cambio, Bs 500 después.
    mockPrisma.booking.aggregate.mockImplementation(({ where }) => {
      const gte: Date = where.OR[0].serviceEndedAt.gte;
      return Promise.resolve({
        _sum: { commissionAmount: gte < new Date('2026-06-01T00:00:00Z') ? 1000 : 500 },
      });
    });
    const plans = [plan('2026-01-01T00:00:00Z', DEFAULT_ALLOCATION), plan('2026-06-01T00:00:00Z', ALL_TO_INVESTORS)];
    const r = await allocateBetween(plans, new Date('2026-05-01T00:00:00Z'), new Date('2026-07-01T00:00:00Z'));
    expect(r.commission).toBe(1500);
    expect(r.allocated.SUELDOS).toBe(350); // solo del tramo viejo
    expect(r.allocated.INVERSORES).toBe(150 + 500);
    expect(sum(r.allocated)).toBe(1500);
  });

  it('solo cuenta reservas COMPLETED e incluye las viejas sin serviceEndedAt', async () => {
    mockPrisma.booking.aggregate.mockResolvedValue({ _sum: { commissionAmount: 0 } });
    await allocateBetween([], new Date('2026-01-01T00:00:00Z'), new Date('2026-02-01T00:00:00Z'));
    const where = mockPrisma.booking.aggregate.mock.calls[0][0].where;
    expect(where.status).toBe('COMPLETED');
    expect(where.OR[1]).toEqual(expect.objectContaining({ serviceEndedAt: null }));
  });
});

describe('getAllocationReport', () => {
  it('disponible = asignado − gastado, y el fondo informa cuántos casos de Bs 2.000 cubre', async () => {
    mockPrisma.commissionAllocationPlan.findMany.mockResolvedValue([]);
    mockPrisma.booking.aggregate.mockResolvedValue({ _sum: { commissionAmount: 40000 } });
    mockPrisma.commissionBucketMovement.groupBy.mockResolvedValue([
      { bucket: 'FONDO_GARANTIA', _sum: { amount: 1500 } },
      { bucket: 'SUELDOS', _sum: { amount: 20000 } },
    ]);
    const r = await getAllocationReport('all');
    const fund = r.buckets.find((b) => b.key === 'FONDO_GARANTIA')!;
    // El mock devuelve 40000 por consulta; 'all' es un solo tramo con el plan por defecto.
    expect(fund.allocatedAllTime).toBe(6000);
    expect(fund.available).toBe(4500);
    expect(r.fund).toEqual(expect.objectContaining({ claimCapBs: 2000, casesCovered: 2, targetCases: 3, targetAmount: 6000 }));
    expect(r.fund.progressPct).toBeCloseTo(75, 5);
    // Gastar más de lo asignado se ve como disponible negativo (el modelo no alcanza).
    const salaries = r.buckets.find((b) => b.key === 'SUELDOS')!;
    expect(salaries.available).toBe(14000 - 20000);
    expect(r.plan.isDefault).toBe(true);
  });

  it('ignora una versión guardada corrupta en vez de romper el reporte', async () => {
    mockPrisma.commissionAllocationPlan.findMany.mockResolvedValue([
      { id: 'x', effectiveFrom: new Date('2026-01-01'), buckets: [{ key: 'SUELDOS', pct: 120 }], note: null, createdBy: null },
    ]);
    mockPrisma.booking.aggregate.mockResolvedValue({ _sum: { commissionAmount: 100 } });
    mockPrisma.commissionBucketMovement.groupBy.mockResolvedValue([]);
    const r = await getAllocationReport('month');
    expect(r.plan.isDefault).toBe(true);
  });
});

describe('un solo lugar para la comisión', () => {
  it('la comisión ya no se puede editar por la vía genérica de Admin > Técnica', () => {
    expect(ALLOWED_SETTING_KEYS as readonly string[]).not.toContain('platformCommissionPct');
  });
});
