/**
 * initPayment con impuestos en pausa: una reserva creada antes de la pausa (128 = 110 + 18)
 * debe cobrarse por 110 — el QR se emite por el monto sin impuesto y la reserva queda con
 * taxAmount 0. Con impuestos activos se cobra el total original.
 */
import { initPayment } from '../../src/modules/booking-service/booking.service';
import prisma from '../../src/config/database';
import { env } from '../../src/config/env';
import { invalidatePricingConfig } from '../../src/modules/pricing/pricing.service';
import * as paymentQrAmountService from '../../src/services/payment-qr-amount.service';
import * as sipService from '../../src/services/sip.service';

jest.mock('../../src/config/database', () => {
  const db = {
    booking: { findFirst: jest.fn(), findUnique: jest.fn(), update: jest.fn(), updateMany: jest.fn() },
    clientProfile: { updateMany: jest.fn() },
    user: { findUnique: jest.fn() },
    walletTransaction: { aggregate: jest.fn(), create: jest.fn() },
    caregiverCommissionOverride: { findMany: jest.fn().mockResolvedValue([]) },
    appSettings: { findUnique: jest.fn() },
    $queryRaw: jest.fn().mockResolvedValue([]),
    $transaction: jest.fn(),
  };
  db.$transaction.mockImplementation((fn: (tx: unknown) => unknown) => fn(db));
  return { __esModule: true, default: db };
});
jest.mock('../../src/services/notification.service', () => ({}));
jest.mock('../../src/services/blockchain.service', () => ({ blockchainService: {} }));
jest.mock('../../src/services/firebase.service', () => ({
  sendPushToUser: jest.fn().mockResolvedValue(undefined),
  sendPushToAdmins: jest.fn().mockResolvedValue(undefined),
}));
jest.mock('../../src/shared/analytics', () => ({ track: jest.fn() }));
jest.mock('../../src/services/sip.service', () => ({
  generateQr: jest.fn().mockResolvedValue({ idQr: 'q1', idTransaccion: 't1', imagenQr: 'AAA' }),
  notifyAdminsSipFailure: jest.fn().mockResolvedValue(undefined),
}));
jest.mock('../../src/services/payment-qr-amount.service', () => ({
  getPaymentQrImageUrlForAmount: jest.fn().mockResolvedValue('https://qr.example/monto.png'),
}));

const db = prisma as unknown as {
  booking: { findFirst: jest.Mock; findUnique: jest.Mock; update: jest.Mock; updateMany: jest.Mock };
  user: { findUnique: jest.Mock };
  appSettings: { findUnique: jest.Mock };
};
/** Llamadas que tocan el impuesto de la reserva (las del NIT del grupo no cuentan). */
const taxUpdates = () => db.booking.updateMany.mock.calls.filter((c) => c[0]?.data && 'taxAmount' in c[0].data);
const qrForAmount = paymentQrAmountService.getPaymentQrImageUrlForAmount as jest.Mock;

const BOOKING = {
  id: 'b1',
  status: 'PENDING_PAYMENT',
  caregiverId: 'c1',
  totalAmount: 128,
  commissionAmount: 10,
  taxAmount: 18,
  walletPaymentAmount: 0,
  sipQrId: null,
  serviceType: 'PASEO',
};

function setSettings(values: Record<string, unknown>) {
  db.appSettings.findUnique.mockImplementation(async ({ where }: { where: { key: string } }) =>
    where.key in values ? { key: where.key, value: JSON.stringify(values[where.key]) } : null
  );
}

const sipBefore = env.SIP_ENABLED;
afterAll(() => {
  (env as { SIP_ENABLED: boolean }).SIP_ENABLED = sipBefore;
});

beforeEach(() => {
  jest.clearAllMocks();
  invalidatePricingConfig();
  (env as { SIP_ENABLED: boolean }).SIP_ENABLED = false;
  db.booking.findFirst.mockResolvedValue({ ...BOOKING });
  db.booking.findUnique.mockResolvedValue({ ...BOOKING });
  db.booking.update.mockResolvedValue({});
  db.booking.updateMany.mockResolvedValue({ count: 1 });
  db.user.findUnique.mockResolvedValue({ balance: 0 });
});

it('impuestos en pausa: el QR se emite por 110 (sin el impuesto) y la reserva queda sin impuesto', async () => {
  setSettings({});
  await initPayment('b1', 'client-1', 'qr');

  expect(qrForAmount).toHaveBeenCalledWith(110);
  const fix = taxUpdates()[0]![0];
  expect(Number(fix.data.totalAmount)).toBe(110);
  expect(Number(fix.data.taxAmount)).toBe(0);
});

it('impuestos aprobados (con SIP): el banco recibe el total con impuesto y no se toca la reserva', async () => {
  (env as { SIP_ENABLED: boolean }).SIP_ENABLED = true;
  setSettings({ taxesEnabled: true });
  await initPayment('b1', 'client-1', 'qr');
  expect((sipService.generateQr as jest.Mock).mock.calls[0][1]).toBe(128);
  expect(taxUpdates()).toHaveLength(0);
});

it('aprobados con SIP apagado: el QR provisional se busca por 128 (el switch basta)', async () => {
  setSettings({ taxesEnabled: true });
  await initPayment('b1', 'client-1', 'qr');
  expect(qrForAmount).toHaveBeenCalledWith(128);
  expect(taxUpdates()).toHaveLength(0);
});

it('SIP encendido pero impuestos sin aprobar: el banco recibe 110', async () => {
  (env as { SIP_ENABLED: boolean }).SIP_ENABLED = true;
  setSettings({});
  await initPayment('b1', 'client-1', 'qr');
  expect((sipService.generateQr as jest.Mock).mock.calls[0][1]).toBe(110);
});

it('varios días (un solo pago): en pausa se quita el impuesto de cada día antes de sumar', async () => {
  setSettings({});
  const lead = { ...BOOKING, bookingGroupId: 'g1' };
  db.booking.findFirst.mockResolvedValue(lead);
  (db.booking as unknown as { findMany: jest.Mock }).findMany = jest.fn().mockResolvedValue([{ id: 'b2', totalAmount: 128 }]);
  await initPayment('b1', 'client-1', 'qr');
  expect(taxUpdates()).toHaveLength(2); // la líder y el otro día
  expect(qrForAmount).toHaveBeenCalledWith(220); // 110 + 110, no 128 + 128
});
