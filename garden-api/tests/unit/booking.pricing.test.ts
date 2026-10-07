/**
 * Extensiones de reserva con comisión variable + impuestos (booking.service.ts).
 * La cotización de una extensión debe:
 *  - usar la comisión del servicio / cuidador-empresa (no una global),
 *  - sumar el 16 % de impuestos SOLO si el admin los aprobó con el switch,
 *  - persistir comisión e impuesto de la extensión (para repartirlos al confirmar).
 */
import { requestWalkExtensionPayment } from '../../src/modules/booking-service/booking.service';
import prisma from '../../src/config/database';
import { invalidatePricingConfig } from '../../src/modules/pricing/pricing.service';
import { env } from '../../src/config/env';

jest.mock('../../src/config/database', () => {
  const db: any = {
    booking: { findFirst: jest.fn(), update: jest.fn() },
    caregiverProfile: { findFirst: jest.fn() },
    adminNotification: { create: jest.fn() },
    caregiverCommissionOverride: { findMany: jest.fn() },
    appSettings: { findUnique: jest.fn() },
    $transaction: jest.fn(async (ops: unknown) => (Array.isArray(ops) ? Promise.all(ops) : ops)),
  };
  return { __esModule: true, default: db, prisma: db };
});

jest.mock('../../src/services/notification.service', () => ({}));
jest.mock('../../src/services/blockchain.service', () => ({ blockchainService: {} }));
jest.mock('../../src/services/firebase.service', () => ({
  sendPushToUser: jest.fn().mockResolvedValue(undefined),
  sendPushToAdmins: jest.fn().mockResolvedValue(undefined),
}));
jest.mock('../../src/shared/analytics', () => ({ track: jest.fn() }));

const db = prisma as unknown as {
  booking: { findFirst: jest.Mock; update: jest.Mock };
  caregiverProfile: { findFirst: jest.Mock };
  caregiverCommissionOverride: { findMany: jest.Mock };
  appSettings: { findUnique: jest.Mock };
};

function setSettings(values: Record<string, unknown>) {
  db.appSettings.findUnique.mockImplementation(async ({ where }: { where: { key: string } }) =>
    where.key in values ? { key: where.key, value: JSON.stringify(values[where.key]) } : null
  );
}

const CAREGIVER = 'c0000000-0000-4000-8000-000000000001';

/** Impuestos activos = el switch del admin aprobado (única condición, pricing.service.ts). */
function taxesOn() {
  setSettings({ taxesEnabled: true });
}

function paseoBooking(pricePerUnit: number) {
  return {
    id: 'b1',
    serviceType: 'PASEO',
    status: 'IN_PROGRESS',
    pricePerUnit,
    caregiverId: CAREGIVER,
    serviceEvents: [],
  };
}

describe('requestWalkExtensionPayment — comisión variable + impuestos', () => {
  const sipBefore = env.SIP_ENABLED;
  afterAll(() => {
    (env as { SIP_ENABLED: boolean }).SIP_ENABLED = sipBefore;
  });
  beforeEach(() => {
    jest.clearAllMocks();
    invalidatePricingConfig();
    db.caregiverCommissionOverride.findMany.mockResolvedValue([]);
    db.caregiverProfile.findFirst.mockResolvedValue({ id: CAREGIVER });
    db.booking.update.mockResolvedValue({});
    (env as { SIP_ENABLED: boolean }).SIP_ENABLED = false;
    setSettings({});
  });

  it('impuestos en pausa (por defecto): solo comisión, sin impuesto — 30 → 33', async () => {
    db.booking.findFirst.mockResolvedValue(paseoBooking(66));

    const res = await requestWalkExtensionPayment('b1', 'client-1', 30, 'manual');

    expect(res.extraAmount).toBe(33);
    const evt = db.booking.update.mock.calls[0][0].data.serviceEvents[0];
    expect(evt).toMatchObject({ extraAmount: 33, extraCommission: 3, extraTax: 0 });
  });

  it('SIP_ENABLED no influye: con SIP encendido y el switch sin aprobar, sigue sin impuesto', async () => {
    (env as { SIP_ENABLED: boolean }).SIP_ENABLED = true;
    db.booking.findFirst.mockResolvedValue(paseoBooking(66));

    const res = await requestWalkExtensionPayment('b1', 'client-1', 30, 'manual');

    expect(res.extraAmount).toBe(33);
    expect(db.booking.update.mock.calls[0][0].data.serviceEvents[0]).toMatchObject({ extraTax: 0 });
  });

  it('comisión 10 % + impuestos 16 % (aprobados, aun con SIP apagado): 30 min de un paseo de Bs 60 (cuidador) cuestan 30 → 33 → 38', async () => {
    taxesOn();
    // pricePerUnit con comisión = 66 (60 × 1.10) → cuidador 60 → 30 min = 30
    db.booking.findFirst.mockResolvedValue(paseoBooking(66));

    const res = await requestWalkExtensionPayment('b1', 'client-1', 30, 'manual');

    expect(res.extraAmount).toBe(38); // 30 + 3 (comisión) = 33; + 5 (16 % de 33 = 5.28) = 38
    const events = db.booking.update.mock.calls[0][0].data.serviceEvents;
    expect(events[0]).toMatchObject({ extraAmount: 38, extraCommission: 3, extraTax: 5 });
    // el cuidador recibe lo suyo íntegro: 38 − 3 − 5 = 30
    expect(events[0].extraAmount - events[0].extraCommission - events[0].extraTax).toBe(30);
  });

  it('una empresa con comisión personalizada del 5 % en paseo paga menos que el resto', async () => {
    taxesOn();
    invalidatePricingConfig();
    db.caregiverCommissionOverride.findMany.mockResolvedValue([
      { caregiverId: CAREGIVER, serviceType: 'PASEO', pct: '5' },
    ]);
    // pricePerUnit con 5 % = 63 → cuidador 60
    db.booking.findFirst.mockResolvedValue(paseoBooking(63));

    const res = await requestWalkExtensionPayment('b1', 'client-1', 60, 'manual');

    // 60 → comisión 3 → 63 → impuestos 10 (16 % de 63 = 10.08) → 73
    expect(res.extraAmount).toBe(73);
    const evt = db.booking.update.mock.calls[0][0].data.serviceEvents[0];
    expect(evt).toMatchObject({ extraCommission: 3, extraTax: 10 });
  });

  it('el impuesto es configurable por el admin (p. ej. 0 % → sin impuestos)', async () => {
    setSettings({ taxesEnabled: true, taxRatePct: 0 });
    db.booking.findFirst.mockResolvedValue(paseoBooking(66));

    const res = await requestWalkExtensionPayment('b1', 'client-1', 60, 'manual');

    expect(res.extraAmount).toBe(66);
    expect(db.booking.update.mock.calls[0][0].data.serviceEvents[0]).toMatchObject({ extraTax: 0 });
  });
});
