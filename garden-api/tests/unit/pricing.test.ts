/**
 * Comisión variable + impuestos (pricing.service.ts).
 * Invariantes de dinero que NO pueden romperse:
 *   total = comisionado + impuesto;  total − comisión − impuesto = precio del cuidador.
 */
import {
  computeClientCharge,
  resolveCommissionPct,
  caregiverNetOf,
  caregiverUnitFromPriced,
  getPricingConfig,
  walk30BasePrice,
  getCommissionRate,
  getTaxRate,
  invalidatePricingConfig,
  type PricingConfig,
} from '../../src/modules/pricing/pricing.service';
import prisma from '../../src/config/database';
import { env } from '../../src/config/env';

jest.mock('../../src/config/database', () => ({
  __esModule: true,
  default: {
    caregiverCommissionOverride: { findMany: jest.fn().mockResolvedValue([]) },
    appSettings: { findUnique: jest.fn().mockResolvedValue(null) },
  },
}));

const mockPrisma = prisma as unknown as {
  caregiverCommissionOverride: { findMany: jest.Mock };
  appSettings: { findUnique: jest.Mock };
};

function cfg(over: Partial<PricingConfig> = {}): PricingConfig {
  return {
    defaultCommissionPct: 10,
    serviceCommissionPct: {},
    overrides: new Map(),
    taxRatePct: 16,
    configuredTaxRatePct: 16,
    taxesEnabled: true,
    taxesActive: true,
    ...over,
  };
}

describe('computeClientCharge', () => {
  it('Bs 100 del cuidador, 10 % comisión, 16 % impuestos → cliente paga 128', () => {
    const c = computeClientCharge(100, 0.1, 0.16);
    expect(c).toEqual({ base: 100, priced: 110, commission: 10, tax: 18, total: 128 });
  });

  it('el neto del cuidador siempre es total − comisión − impuesto = su precio', () => {
    for (const base of [15, 33, 45, 70, 99, 120, 333, 1000]) {
      for (const rate of [0, 0.05, 0.1, 0.125, 0.2]) {
        for (const tax of [0, 0.16]) {
          const c = computeClientCharge(base, rate, tax);
          expect(c.total).toBe(c.priced + c.tax);
          expect(c.total - c.commission - c.tax).toBe(c.base);
          expect(Number.isInteger(c.total)).toBe(true); // los QR por monto exacto son enteros
        }
      }
    }
  });

  it('sin impuesto el resultado coincide con la fórmula histórica (round(base × (1 + comisión)))', () => {
    for (const base of [15, 33, 45, 70, 99]) {
      expect(computeClientCharge(base, 0.1, 0).total).toBe(Math.round(base * 1.1));
    }
  });

  it('comisión 0 % sigue cobrando impuestos', () => {
    expect(computeClientCharge(100, 0, 0.16)).toEqual({ base: 100, priced: 100, commission: 0, tax: 16, total: 116 });
  });
});

describe('resolveCommissionPct — precedencia', () => {
  const caregiverA = 'a0000000-0000-4000-8000-000000000001';
  const caregiverB = 'b0000000-0000-4000-8000-000000000002';

  it('sin nada configurado usa la comisión por defecto', () => {
    expect(resolveCommissionPct(cfg(), 'PASEO', caregiverA)).toBe(10);
  });

  it('la comisión del servicio gana a la por defecto', () => {
    const c = cfg({ serviceCommissionPct: { PASEO: 8, HOSPEDAJE: 12 } });
    expect(resolveCommissionPct(c, 'PASEO', null)).toBe(8);
    expect(resolveCommissionPct(c, 'HOSPEDAJE', caregiverA)).toBe(12);
    expect(resolveCommissionPct(c, 'GUARDERIA', caregiverA)).toBe(10); // sin propia → default
  });

  it('override del cuidador para el servicio > override ALL > servicio > default', () => {
    const c = cfg({
      serviceCommissionPct: { PASEO: 8 },
      overrides: new Map([[caregiverA, { ALL: 5, PASEO: 3 }]]),
    });
    expect(resolveCommissionPct(c, 'PASEO', caregiverA)).toBe(3);
    expect(resolveCommissionPct(c, 'HOSPEDAJE', caregiverA)).toBe(5);
    expect(resolveCommissionPct(c, 'PASEO', caregiverB)).toBe(8); // otro cuidador no se ve afectado
  });

  it('un override de 0 % es válido (no cae al valor por defecto)', () => {
    const c = cfg({ overrides: new Map([[caregiverA, { ALL: 0 }]]) });
    expect(resolveCommissionPct(c, 'PASEO', caregiverA)).toBe(0);
  });
});

describe('caregiverNetOf / caregiverUnitFromPriced', () => {
  it('descuenta comisión e impuesto; reservas viejas sin impuesto siguen igual', () => {
    expect(caregiverNetOf({ totalAmount: 128, commissionAmount: 10, taxAmount: 18 })).toBe(100);
    expect(caregiverNetOf({ totalAmount: 110, commissionAmount: 10 })).toBe(100);
    expect(caregiverNetOf({ totalAmount: '110', commissionAmount: '10', taxAmount: undefined })).toBe(100);
  });

  it('promo: reduce total y comisión por igual → el neto del cuidador no cambia', () => {
    // total 128 (100 + 10 + 18), promo de Bs 8 → total 120, comisión 2, impuesto igual
    expect(caregiverNetOf({ totalAmount: 120, commissionAmount: 2, taxAmount: 18 })).toBe(100);
  });

  it('precio unitario del cuidador desde el precio con comisión', () => {
    expect(caregiverUnitFromPriced(110, 0.1)).toBe(100);
    expect(caregiverUnitFromPriced(55, 0.1)).toBe(50);
  });
});

describe('getPricingConfig (lectura de AppSettings + overrides)', () => {
  beforeEach(() => {
    invalidatePricingConfig();
    jest.clearAllMocks();
    mockPrisma.caregiverCommissionOverride.findMany.mockResolvedValue([]);
    mockPrisma.appSettings.findUnique.mockResolvedValue(null);
  });

  it('defaults: 10 % de comisión; impuestos configurados en 16 % pero EN PAUSA (tasa efectiva 0)', async () => {
    const c = await getPricingConfig();
    expect(c.defaultCommissionPct).toBe(10);
    expect(c.configuredTaxRatePct).toBe(16);
    expect(c.taxesEnabled).toBe(false);
    expect(c.taxesActive).toBe(false);
    expect(c.taxRatePct).toBe(0);
    expect(c.serviceCommissionPct).toEqual({});
    expect(await getTaxRate()).toBe(0);
  });

  describe('interruptor de impuestos (el switch del admin es la ÚNICA condición)', () => {
    const sipBefore = env.SIP_ENABLED;
    const setSip = (v: boolean) => {
      (env as { SIP_ENABLED: boolean }).SIP_ENABLED = v;
    };
    const setTaxesEnabled = (value: string | null) =>
      mockPrisma.appSettings.findUnique.mockImplementation(async ({ where }: { where: { key: string } }) =>
        where.key === 'taxesEnabled' && value !== null ? { key: where.key, value } : null
      );
    afterAll(() => setSip(sipBefore));

    // SIP_ENABLED se prueba en ambos valores para dejar claro que NO influye.
    const cases: Array<[string, string | null, boolean, number]> = [
      ['sin setting, SIP apagado', null, false, 0],
      ['sin setting, SIP encendido', null, true, 0],
      ['pausado, SIP encendido', 'false', true, 0],
      ['valor corrupto', '"si"', true, 0],
      ['aprobado, SIP apagado', 'true', false, 16],
      ['aprobado, SIP encendido', 'true', true, 16],
    ];
    it.each(cases)('%s (taxesEnabled=%s, SIP=%s) → tasa efectiva %i %%', async (_name, setting, sip, expectedPct) => {
      invalidatePricingConfig();
      setSip(sip);
      setTaxesEnabled(setting);
      const c = await getPricingConfig();
      expect(c.taxRatePct).toBe(expectedPct);
      expect(c.taxesActive).toBe(expectedPct > 0);
      expect(c.configuredTaxRatePct).toBe(16);
      expect(await getTaxRate()).toBeCloseTo(expectedPct / 100);
    });

    it('si la base falla al leer el switch, NO se cobra impuesto', async () => {
      invalidatePricingConfig();
      setSip(true);
      mockPrisma.appSettings.findUnique.mockRejectedValue(new Error('db caída'));
      expect((await getPricingConfig()).taxRatePct).toBe(0);
    });

    it('en pausa, una reserva nueva cobra solo la comisión: Bs 100 → 110 (sin impuesto)', async () => {
      invalidatePricingConfig();
      setSip(false);
      setTaxesEnabled(null);
      const c = await getPricingConfig();
      expect(computeClientCharge(100, 0.1, c.taxRatePct / 100)).toEqual({ base: 100, priced: 110, commission: 10, tax: 0, total: 110 });
    });
  });

  it('carga overrides por cuidador y servicio, ignorando servicios desconocidos', async () => {
    mockPrisma.caregiverCommissionOverride.findMany.mockResolvedValue([
      { caregiverId: 'c1', serviceType: 'ALL', pct: '5' },
      { caregiverId: 'c1', serviceType: 'PASEO', pct: '3.5' },
      { caregiverId: 'c2', serviceType: 'BASURA', pct: '99' },
    ]);
    const c = await getPricingConfig();
    expect(c.overrides.get('c1')).toEqual({ ALL: 5, PASEO: 3.5 });
    expect(c.overrides.has('c2')).toBe(false);
    expect(await getCommissionRate('PASEO', 'c1')).toBeCloseTo(0.035);
    expect(await getCommissionRate('HOSPEDAJE', 'c1')).toBeCloseTo(0.05);
  });

  it('valores fuera de rango en AppSettings se ignoran (vuelven al default)', async () => {
    mockPrisma.appSettings.findUnique.mockImplementation(async ({ where }: { where: { key: string } }) => {
      if (where.key === 'platformCommissionPct') return { key: where.key, value: '900' };
      if (where.key === 'taxRatePct') return { key: where.key, value: '-4' };
      if (where.key === 'commissionPctPaseo') return { key: where.key, value: '75' };
      if (where.key === 'commissionPctHospedaje') return { key: where.key, value: '7.5' };
      return null;
    });
    const c = await getPricingConfig();
    expect(c.defaultCommissionPct).toBe(10);
    expect(c.configuredTaxRatePct).toBe(16);
    expect(c.serviceCommissionPct).toEqual({ HOSPEDAJE: 7.5 });
  });
});

describe('walk30BasePrice (paseo de 30 min)', () => {
  it('usa el precio que fijó el cuidador para 30 min, aunque no sea la mitad del de 60', () => {
    expect(walk30BasePrice(30, 50)).toBe(30);
    expect(walk30BasePrice(20, 50)).toBe(20);
  });

  it('sin precio de 30 min cargado (null o 0), cae a la mitad del de 60', () => {
    expect(walk30BasePrice(null, 50)).toBe(25);
    expect(walk30BasePrice(0, 45)).toBe(23);
    expect(walk30BasePrice(undefined, '60')).toBe(30);
  });

  it('sin ningún precio de paseo devuelve null', () => {
    expect(walk30BasePrice(null, null)).toBeNull();
    expect(walk30BasePrice(0, 0)).toBeNull();
  });

  it('lo que ve el cliente en el perfil = lo que se cobra (misma regla + misma comisión)', () => {
    const shown = Math.round(walk30BasePrice(30, 50)! * 1.19);
    const charged = computeClientCharge(walk30BasePrice(30, 50)!, 0.19, 0).total;
    expect(shown).toBe(36);
    expect(charged).toBe(36);
  });
});
