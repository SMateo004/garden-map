/**
 * Ayuda con el pago desde el QR (payment-help.service.ts) y pago incompleto
 * (payment-review.service.ts, INCOMPLETE).
 */
import { requestPaymentHelp } from '../../src/modules/payment-service/payment-help.service';
import { reviewAutoApprovedPayment } from '../../src/modules/payment-service/payment-review.service';
import prisma from '../../src/config/database';
import { notifyAdmins } from '../../src/services/firebase.service';
import { recordSupportExchange } from '../../src/modules/support-chat/support-chat.service';
import { getPaymentQrImageUrl } from '../../src/services/payment-qr.service';

jest.mock('../../src/config/database', () => {
  const db = {
    booking: { findFirst: jest.fn(), findUnique: jest.fn(), update: jest.fn(), updateMany: jest.fn() },
    user: { update: jest.fn() },
    walletTransaction: { create: jest.fn(), aggregate: jest.fn() },
    notification: { create: jest.fn() },
    adminAction: { create: jest.fn() },
    $queryRaw: jest.fn().mockResolvedValue([]),
    $transaction: jest.fn(),
  };
  db.$transaction.mockImplementation((fn: (tx: unknown) => unknown) => fn(db));
  return { __esModule: true, default: db };
});
jest.mock('../../src/services/firebase.service', () => ({
  notifyAdmins: jest.fn().mockResolvedValue(undefined),
  sendPushToUser: jest.fn().mockResolvedValue(undefined),
}));
jest.mock('../../src/modules/support-chat/support-chat.service', () => ({
  recordSupportExchange: jest.fn().mockResolvedValue({ threadId: 't1', status: 'BOT' }),
}));
jest.mock('../../src/services/payment-qr.service', () => ({ getPaymentQrImageUrl: jest.fn() }));
jest.mock('../../src/utils/settings-cache', () => ({ getNumericSetting: jest.fn().mockResolvedValue(15) }));

const db = prisma as unknown as {
  booking: { findFirst: jest.Mock; findUnique: jest.Mock; update: jest.Mock; updateMany: jest.Mock };
  user: { update: jest.Mock };
  walletTransaction: { create: jest.Mock; aggregate: jest.Mock };
  notification: { create: jest.Mock };
};

const pending = {
  id: 'abcd1234-0000', status: 'PENDING_PAYMENT', serviceType: 'PASEO',
  qrExpiresAt: new Date(Date.now() + 2 * 60_000),
  totalAmount: 100, walletPaymentAmount: 20, donationAmount: 0, paymentExpectedAmount: null,
};

beforeEach(() => jest.clearAllMocks());

describe('ayuda con el pago', () => {
  it('banco no lee el QR: muestra el QR sin monto y queda en el chat de soporte', async () => {
    db.booking.findFirst.mockResolvedValue(pending);
    (getPaymentQrImageUrl as jest.Mock).mockResolvedValue('https://cdn/qr-paseo.png');
    const r = await requestPaymentHelp({ bookingId: pending.id, clientId: 'c1', issue: 'QR_NOT_WORKING' });

    expect(r.action).toBe('SHOW_FALLBACK_QR');
    expect(r.fallbackQrUrl).toBe('https://cdn/qr-paseo.png');
    expect(r.message).toMatch(/Bs 80\.00/); // 100 − 20 de billetera
    expect(recordSupportExchange).toHaveBeenCalledWith('c1', expect.stringContaining('ABCD1234'), r.message, { escalate: false });
    expect(notifyAdmins).toHaveBeenCalledWith(expect.any(String), expect.any(String), {
      type: 'ADMIN_PAYMENT_HELP', bookingId: pending.id,
    });
  });

  it('sin QR alternativo: deriva a un asesor', async () => {
    db.booking.findFirst.mockResolvedValue(pending);
    (getPaymentQrImageUrl as jest.Mock).mockResolvedValue(null);
    const r = await requestPaymentHelp({ bookingId: pending.id, clientId: 'c1', issue: 'QR_NOT_WORKING' });
    expect(r.action).toBe('OPEN_SUPPORT');
    expect((recordSupportExchange as jest.Mock).mock.calls[0][3]).toEqual({ escalate: true });
  });

  it('más tiempo: renueva la vigencia del QR sin acortarla', async () => {
    db.booking.findFirst.mockResolvedValue(pending);
    db.booking.updateMany.mockResolvedValue({ count: 1 });
    const r = await requestPaymentHelp({ bookingId: pending.id, clientId: 'c1', issue: 'MORE_TIME' });
    expect(r.action).toBe('EXTEND_QR');
    const where = db.booking.updateMany.mock.calls[0][0].where;
    expect(where.status).toBe('PENDING_PAYMENT');
    expect(where.qrExpiresAt.gt).toBeInstanceOf(Date);
    expect(new Date(r.qrExpiresAt!).getTime()).toBeGreaterThan(Date.now() + 14 * 60_000);
  });

  it('pagó otro monto: avisa el pago y lo escala con el monto que dice', async () => {
    db.booking.findFirst.mockResolvedValue(pending);
    const r = await requestPaymentHelp({ bookingId: pending.id, clientId: 'c1', issue: 'WRONG_AMOUNT', paidAmount: 60 });
    expect(r.action).toBe('DECLARE');
    const [, clientText, , opts] = (recordSupportExchange as jest.Mock).mock.calls[0];
    expect(clientText).toMatch(/pagó Bs 60\.00 \(debía Bs 80\.00\)/);
    expect(opts).toEqual({ escalate: true });
  });

  it('no aplica si la reserva ya no tiene pago pendiente', async () => {
    db.booking.findFirst.mockResolvedValue({ ...pending, status: 'CONFIRMED' });
    await expect(requestPaymentHelp({ bookingId: pending.id, clientId: 'c1', issue: 'OTHER' }))
      .rejects.toMatchObject({ code: 'NOT_PAYING' });
  });
});

describe('pago incompleto (admin)', () => {
  const paid = {
    id: 'b1', clientId: 'c1', totalAmount: 100, walletPaymentAmount: 0, donationAmount: 0,
    paymentExpectedAmount: null, paymentAutoApprovedAt: null, paymentReviewedAt: null, paidAt: new Date(),
  };

  it('cobra de la billetera solo la diferencia con lo que llegó', async () => {
    db.booking.findUnique.mockResolvedValue(paid);
    db.walletTransaction.aggregate.mockResolvedValue({ _sum: { amount: null } });
    db.user.update.mockResolvedValue({ balance: -30 });
    const r = await reviewAutoApprovedPayment('b1', 'admin1', 'INCOMPLETE', 70);

    expect(r.chargedAmount).toBe(30);
    expect(db.user.update.mock.calls[0][0].data).toEqual({ balance: { decrement: 30 } });
    expect(db.walletTransaction.create.mock.calls[0][0].data).toMatchObject({
      type: 'PAYMENT_INCOMPLETE', amount: 30, balance: -30,
    });
    expect(db.booking.update.mock.calls[0][0].data).toMatchObject({ paymentReviewOutcome: 'INCOMPLETE' });
  });

  it('exige que el pago ya esté aprobado', async () => {
    db.booking.findUnique.mockResolvedValue({ ...paid, paidAt: null });
    await expect(reviewAutoApprovedPayment('b1', 'admin1', 'INCOMPLETE', 70)).rejects.toThrow(/Primero aprueba/);
  });

  it('si llegó todo, no cobra nada', async () => {
    db.booking.findUnique.mockResolvedValue(paid);
    db.walletTransaction.aggregate.mockResolvedValue({ _sum: { amount: null } });
    const r = await reviewAutoApprovedPayment('b1', 'admin1', 'INCOMPLETE', 100);
    expect(r.chargedAmount).toBe(0);
    expect(db.user.update).not.toHaveBeenCalled();
    expect(db.notification.create).not.toHaveBeenCalled();
  });
});
