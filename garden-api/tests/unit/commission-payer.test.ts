/**
 * Quién paga la comisión. 'CLIENT' (de siempre): el dueño paga precio + comisión +
 * impuesto. 'CAREGIVER': el dueño paga precio + impuesto y la comisión se descuenta del
 * cuidador. En ambos casos lo que cobra el cuidador sale de total − comisión − impuesto.
 */
import {
  computeClientCharge,
  caregiverUnitFromPriced,
  caregiverNetOf,
  clientPaidCommission,
  clientMarkupPct,
  normalizePayer,
  type PricingConfig,
} from '../../src/modules/pricing/pricing.service';

jest.mock('../../src/config/database', () => ({ __esModule: true, default: {} }));

describe('computeClientCharge', () => {
  it('CLIENT: el dueño paga la comisión encima (modelo de siempre)', () => {
    const c = computeClientCharge(100, 0.1, 0.16);
    expect(c).toEqual({ base: 100, priced: 110, commission: 10, tax: 18, total: 128 });
    expect(caregiverNetOf({ totalAmount: c.total, commissionAmount: c.commission, taxAmount: c.tax })).toBe(100);
  });

  it('CAREGIVER: el dueño ve el precio del cuidador y la comisión se le descuenta al cuidador', () => {
    const c = computeClientCharge(100, 0.1, 0.16, 'CAREGIVER');
    expect(c).toEqual({ base: 100, priced: 100, commission: 10, tax: 16, total: 116 });
    expect(caregiverNetOf({ totalAmount: c.total, commissionAmount: c.commission, taxAmount: c.tax })).toBe(90);
  });

  it('sin impuestos (en pausa) y con montos que redondean', () => {
    expect(computeClientCharge(55, 0.12, 0, 'CAREGIVER')).toEqual({ base: 55, priced: 55, commission: 7, tax: 0, total: 55 });
    expect(computeClientCharge(55, 0.12, 0)).toEqual({ base: 55, priced: 62, commission: 7, tax: 0, total: 62 });
  });

  it('GARDEN cobra la misma comisión con cualquiera de los dos pagadores', () => {
    for (const base of [1, 17, 40, 99, 250, 1234]) {
      for (const rate of [0, 0.05, 0.1, 0.15, 0.5]) {
        const a = computeClientCharge(base, rate, 0);
        const b = computeClientCharge(base, rate, 0, 'CAREGIVER');
        expect(Math.abs(a.commission - b.commission)).toBeLessThanOrEqual(1); // solo redondeo
        // El neto nunca es negativo ni mayor que el precio del cuidador.
        const net = caregiverNetOf({ totalAmount: b.total, commissionAmount: b.commission, taxAmount: b.tax });
        expect(net).toBeGreaterThanOrEqual(0);
        expect(net).toBeLessThanOrEqual(base);
      }
    }
  });

  it('valores raros no rompen el cálculo', () => {
    expect(computeClientCharge(-50, 0.1, 0).total).toBe(0);
    expect(computeClientCharge(100, -0.1, 0).commission).toBe(0);
  });
});

describe('caregiverUnitFromPriced', () => {
  it('deshace el recargo solo si lo pagó el dueño', () => {
    expect(caregiverUnitFromPriced(110, 0.1)).toBe(100);
    expect(caregiverUnitFromPriced(100, 0.1, 'CAREGIVER')).toBe(100);
  });
});

describe('clientPaidCommission', () => {
  it('la comisión que salió del bolsillo del dueño', () => {
    expect(clientPaidCommission({ commissionAmount: 10 })).toBe(10);
    expect(clientPaidCommission({ commissionAmount: 10, commissionPaidBy: 'CLIENT' })).toBe(10);
    expect(clientPaidCommission({ commissionAmount: 10, commissionPaidBy: 'CAREGIVER' })).toBe(0);
  });
});

describe('normalizePayer y recargo que ve el dueño', () => {
  it('cualquier valor desconocido es CLIENT', () => {
    expect(normalizePayer('CAREGIVER')).toBe('CAREGIVER');
    for (const v of ['caregiver', '', null, undefined, 'X', 1]) expect(normalizePayer(v)).toBe('CLIENT');
  });

  it('el listado no muestra recargo para quien paga su comisión', () => {
    const cfg = {
      defaultCommissionPct: 10,
      serviceCommissionPct: { PASEO: 12 },
      overrides: new Map([['cg-override', { PASEO: 8 }]]),
      caregiverPaysCommission: new Set(['cg-pays']),
      taxRatePct: 0,
      configuredTaxRatePct: 16,
      taxesEnabled: false,
      taxesActive: false,
    } as unknown as PricingConfig;
    expect(clientMarkupPct(cfg, 'PASEO', 'cg-normal')).toBe(12);
    expect(clientMarkupPct(cfg, 'PASEO', 'cg-override')).toBe(8);
    expect(clientMarkupPct(cfg, 'PASEO', 'cg-pays')).toBe(0);
    expect(clientMarkupPct(cfg, 'HOSPEDAJE', null)).toBe(10);
  });
});
