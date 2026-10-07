/**
 * Impuestos en pausa (pricing.service.ts + taxes.service.ts + PUT /admin/pricing/taxes).
 * Lo que no puede fallar en producción:
 *  - sin switch aprobado + pasarela activa, ninguna reserva paga impuesto;
 *  - una reserva impaga creada con impuesto lo pierde antes de pagar, sin tocar comisión ni cuidador;
 *  - lo ya pagado (o pagado en parte con billetera) no se toca;
 *  - el switch del admin es la única condición (SIP_ENABLED no influye);
 *  - los Términos no mencionan impuestos mientras estén en pausa.
 */
import express from 'express';
import request from 'supertest';
import prisma from '../../src/config/database';
import { env } from '../../src/config/env';
import { invalidatePricingConfig, caregiverNetOf } from '../../src/modules/pricing/pricing.service';
import { stripTaxFromUnpaidBooking, stripTaxFromAllUnpaidBookings } from '../../src/modules/pricing/taxes.service';
import pricingAdminRouter from '../../src/modules/pricing/pricing.admin';
import { errorHandler } from '../../src/shared/error-handler';
import { SECTIONS_TERMS, termsSections } from '../../src/modules/legal/legal.routes';
import { TAX_CLAUSE_REPLACEMENTS } from '../../src/modules/legal/tax-clauses';

jest.mock('../../src/config/database', () => {
  const db = {
    booking: { findUnique: jest.fn(), findMany: jest.fn(), updateMany: jest.fn() },
    caregiverCommissionOverride: { findMany: jest.fn().mockResolvedValue([]) },
    appSettings: { findUnique: jest.fn(), upsert: jest.fn().mockResolvedValue({}) },
    $transaction: jest.fn(),
  };
  db.$transaction.mockImplementation((fn: (tx: unknown) => unknown) => fn(db));
  return { __esModule: true, default: db };
});
jest.mock('../../src/services/audit.service', () => ({ auditLog: jest.fn() }));
jest.mock('../../src/services/sip.service', () => ({ disableQr: jest.fn().mockResolvedValue(undefined) }));
jest.mock('../../src/shared/cache', () => ({ delByPrefix: jest.fn().mockResolvedValue(undefined) }));

const db = prisma as unknown as {
  booking: { findUnique: jest.Mock; findMany: jest.Mock; updateMany: jest.Mock };
  appSettings: { findUnique: jest.Mock; upsert: jest.Mock };
};
const sip = jest.requireMock('../../src/services/sip.service') as { disableQr: jest.Mock };

const setSip = (v: boolean) => {
  (env as { SIP_ENABLED: boolean }).SIP_ENABLED = v;
};
function setSettings(values: Record<string, unknown>) {
  db.appSettings.findUnique.mockImplementation(async ({ where }: { where: { key: string } }) =>
    where.key in values ? { key: where.key, value: JSON.stringify(values[where.key]) } : null
  );
}

/** Reserva de Bs 100 del cuidador, 10 % comisión, 16 % impuesto: 110 + 18 = 128. */
function taxedBooking(over: Record<string, unknown> = {}) {
  return {
    status: 'PENDING_PAYMENT',
    totalAmount: 128,
    commissionAmount: 10,
    taxAmount: 18,
    walletPaymentAmount: 0,
    sipQrId: null,
    ...over,
  };
}

const sipBefore = env.SIP_ENABLED;
afterAll(() => setSip(sipBefore));

beforeEach(() => {
  jest.clearAllMocks();
  invalidatePricingConfig();
  setSip(false);
  setSettings({});
  db.booking.updateMany.mockResolvedValue({ count: 1 });
});

describe('stripTaxFromUnpaidBooking', () => {
  it('quita el impuesto del total: 128 → 110; la comisión y lo del cuidador no cambian', async () => {
    db.booking.findUnique.mockResolvedValue(taxedBooking());
    const r = await stripTaxFromUnpaidBooking(prisma as never, 'b1');

    expect(r).toEqual({ removed: 18, hadSipQr: false });
    const call = db.booking.updateMany.mock.calls[0][0];
    expect(Number(call.data.totalAmount)).toBe(110);
    expect(Number(call.data.taxAmount)).toBe(0);
    // El QR con el monto viejo se borra: el próximo pago genera uno nuevo con 110.
    expect(call.data).toMatchObject({ qrId: null, qrImageUrl: null, qrExpiresAt: null, sipQrId: null });
    // UPDATE condicional: si otra request ya pagó o corrigió la reserva, no hace nada.
    expect(call.where).toMatchObject({ id: 'b1', taxAmount: 18, totalAmount: 128, walletPaymentAmount: 0 });
    expect(call.where.status.in).toEqual(['PENDING_MG', 'PENDING_PAYMENT']);
    // Lo del cuidador: antes 128 − 10 − 18 = 100; después 110 − 10 − 0 = 100.
    expect(caregiverNetOf({ totalAmount: 110, commissionAmount: 10, taxAmount: 0 })).toBe(
      caregiverNetOf({ totalAmount: 128, commissionAmount: 10, taxAmount: 18 })
    );
  });

  it.each([
    ['ya pagada (CONFIRMED)', { status: 'CONFIRMED' }],
    ['pago en revisión (PAYMENT_PENDING_APPROVAL)', { status: 'PAYMENT_PENDING_APPROVAL' }],
    ['completada', { status: 'COMPLETED' }],
    ['pagó una parte con billetera', { walletPaymentAmount: 40 }],
    ['ya no tiene impuesto', { taxAmount: 0, totalAmount: 110 }],
  ])('no toca una reserva %s', async (_n, over) => {
    db.booking.findUnique.mockResolvedValue(taxedBooking(over));
    const r = await stripTaxFromUnpaidBooking(prisma as never, 'b1');
    expect(r.removed).toBe(0);
    expect(db.booking.updateMany).not.toHaveBeenCalled();
  });

  it('si otra request la cambió en paralelo (count 0) no informa nada quitado', async () => {
    db.booking.findUnique.mockResolvedValue(taxedBooking());
    db.booking.updateMany.mockResolvedValue({ count: 0 });
    expect((await stripTaxFromUnpaidBooking(prisma as never, 'b1')).removed).toBe(0);
  });

  it('avisa que había un QR del banco con el monto viejo', async () => {
    db.booking.findUnique.mockResolvedValue(taxedBooking({ sipQrId: 'sip-1' }));
    expect(await stripTaxFromUnpaidBooking(prisma as never, 'b1')).toEqual({ removed: 18, hadSipQr: true });
  });
});

describe('stripTaxFromAllUnpaidBookings (barrido al arrancar / al pausar)', () => {
  it('en pausa: corrige todas las impagas con impuesto y suma lo quitado', async () => {
    db.booking.findMany.mockResolvedValue([{ id: 'b1' }, { id: 'b2' }]);
    db.booking.findUnique
      .mockResolvedValueOnce(taxedBooking())
      .mockResolvedValueOnce(taxedBooking({ totalAmount: 64, commissionAmount: 5, taxAmount: 9 }));
    const r = await stripTaxFromAllUnpaidBookings();
    expect(r).toEqual({ bookings: 2, totalRemoved: 27 });
    expect(db.booking.findMany.mock.calls[0][0].where).toMatchObject({ taxAmount: { gt: 0 }, walletPaymentAmount: 0 });
  });

  it('con impuestos ACTIVOS no toca nada', async () => {
    setSettings({ taxesEnabled: true });
    const r = await stripTaxFromAllUnpaidBookings();
    expect(r).toEqual({ bookings: 0, totalRemoved: 0 });
    expect(db.booking.findMany).not.toHaveBeenCalled();
  });

  it('si había un QR del banco (SIP) con el monto viejo, lo inhabilita', async () => {
    setSip(true); // SIP encendido, impuestos sin aprobar → en pausa
    db.booking.findMany.mockResolvedValue([{ id: 'b1' }]);
    db.booking.findUnique.mockResolvedValue(taxedBooking({ sipQrId: 'sip-1' }));
    await stripTaxFromAllUnpaidBookings();
    expect(sip.disableQr).toHaveBeenCalledWith('b1');
  });

  it('un error en una reserva no frena el resto', async () => {
    db.booking.findMany.mockResolvedValue([{ id: 'b1' }, { id: 'b2' }]);
    db.booking.findUnique.mockRejectedValueOnce(new Error('timeout')).mockResolvedValueOnce(taxedBooking());
    expect(await stripTaxFromAllUnpaidBookings()).toEqual({ bookings: 1, totalRemoved: 18 });
  });
});

describe('PUT /admin/pricing/taxes (switch del admin)', () => {
  function app() {
    const a = express();
    a.use(express.json());
    a.use((req, _res, next) => {
      (req as unknown as { user: { userId: string } }).user = { userId: 'admin-1' };
      next();
    });
    a.use('/pricing', pricingAdminRouter);
    a.use(errorHandler);
    return a;
  }


  it('exige confirmación explícita', async () => {
    const res = await request(app()).put('/pricing/taxes').send({ enabled: false });
    expect(res.status).toBe(400);
    expect(db.appSettings.upsert).not.toHaveBeenCalled();
  });

  it('aprobar (con SIP apagado) guarda el switch y desde ahí se cobra 16 % — no depende de SIP', async () => {
    setSip(false);
    db.appSettings.upsert.mockImplementation(async (args: { create: { value: string } }) => {
      setSettings({ taxesEnabled: JSON.parse(args.create.value) });
      return {};
    });
    const res = await request(app()).put('/pricing/taxes').send({ enabled: true, confirm: true });
    expect(res.status).toBe(200);
    expect(db.appSettings.upsert.mock.calls[0][0]).toMatchObject({
      where: { key: 'taxesEnabled' },
      create: { value: 'true' },
    });
    expect(res.body.data.taxes).toMatchObject({ enabled: true, active: true, effectiveRatePct: 16 });
    expect(db.booking.findMany).not.toHaveBeenCalled(); // activar no reprecia reservas existentes
  });

  it('pausar se puede siempre y corrige las reservas impagas', async () => {
    setSettings({ taxesEnabled: true });
    db.appSettings.upsert.mockImplementation(async () => {
      setSettings({ taxesEnabled: false });
      return {};
    });
    db.booking.findMany.mockResolvedValue([{ id: 'b1' }]);
    db.booking.findUnique.mockResolvedValue(taxedBooking());
    const res = await request(app()).put('/pricing/taxes').send({ enabled: false, confirm: true });
    expect(res.status).toBe(200);
    expect(res.body.data.taxes).toMatchObject({ enabled: false, active: false, effectiveRatePct: 0 });
    expect(res.body.data.unpaidBookingsAdjusted).toEqual({ bookings: 1, totalRemoved: 18 });
  });

  it('GET devuelve la tasa CONFIGURADA (para no borrarla al guardar comisiones) y el estado aparte', async () => {
    const res = await request(app()).get('/pricing');
    expect(res.status).toBe(200);
    expect(res.body.data.taxRatePct).toBe(16);
    expect(res.body.data.taxes).toMatchObject({ enabled: false, active: false, effectiveRatePct: 0 });
    expect(res.body.data.taxes).not.toHaveProperty('paymentGatewayActive');
  });
});

describe('Términos: sin menciones de impuestos mientras estén en pausa', () => {
  const all = (secs: Array<{ body: string }>) => secs.map((s) => s.body).join('\n');

  it('cada frase a reemplazar existe en los Términos (si se edita el texto, esta prueba avisa)', () => {
    const text = all(SECTIONS_TERMS);
    for (const [from] of TAX_CLAUSE_REPLACEMENTS) expect(text).toContain(from);
  });

  it('en pausa: la sección de precios no habla de impuestos, IVA, IT ni del 16 %', () => {
    const s6 = termsSections(false).find((s) => s.title.startsWith('6.'))!.body;
    expect(s6).not.toMatch(/impuesto|\bIVA\b|\bIT\b|16 ?%|Bs\. 128|Bs\. 18\b/i);
    expect(s6).toContain('Bs. 110');
  });

  it('activos: el texto original queda intacto', () => {
    expect(termsSections(true)).toBe(SECTIONS_TERMS);
  });
});
