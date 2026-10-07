/**
 * Cancelar una reserva sin pagar que tenía un pago combinado en curso
 * (billetera + QR): la parte que ya se descontó de la billetera vuelve al
 * cliente. Antes cancelBooking() la cerraba con reembolso 0 y esa parte se
 * perdía (qr-expiry.job.ts sí la devolvía, pero solo procesa PENDING_PAYMENT).
 */
import { cancelBooking } from '../../src/modules/booking-service/booking.service';
import prisma from '../../src/config/database';

jest.mock('../../src/config/database', () => {
  const db = {
    booking: { findFirst: jest.fn(), findUnique: jest.fn(), count: jest.fn(), update: jest.fn(), updateMany: jest.fn() },
    user: { update: jest.fn() },
    walletTransaction: { create: jest.fn() },
    notification: { create: jest.fn() },
    caregiverProfile: { findUnique: jest.fn() },
    appSettings: { findUnique: jest.fn().mockResolvedValue(null) },
    $queryRaw: jest.fn().mockResolvedValue([]),
    $transaction: jest.fn(),
  };
  db.$transaction.mockImplementation((fn: (tx: unknown) => unknown) => fn(db));
  return { __esModule: true, default: db };
});
jest.mock('../../src/services/firebase.service', () => ({
  sendPushToUser: jest.fn().mockResolvedValue(undefined),
  sendPushToAdmins: jest.fn().mockResolvedValue(undefined),
}));
jest.mock('../../src/services/notification.service', () => ({
  onClientCancelled: jest.fn().mockResolvedValue(undefined),
  onRefundProcessed: jest.fn().mockResolvedValue(undefined),
}));
jest.mock('../../src/services/audit.service', () => ({ auditLog: jest.fn() }));
jest.mock('../../src/services/blockchain.service', () => ({ blockchainService: {} }));
jest.mock('../../src/services/chain-registry.service', () => ({
  enqueueBookingCancel: jest.fn().mockResolvedValue(undefined),
  enqueueSafely: jest.fn(),
}));
jest.mock('../../src/shared/analytics', () => ({ track: jest.fn() }));

const db = prisma as unknown as {
  booking: { findFirst: jest.Mock; findUnique: jest.Mock; update: jest.Mock; updateMany: jest.Mock };
  user: { update: jest.Mock };
  walletTransaction: { create: jest.Mock };
  notification: { create: jest.Mock };
  caregiverProfile: { findUnique: jest.Mock };
  $queryRaw: jest.Mock;
};

const unpaid = {
  id: 'b1', clientId: 'client-1', caregiverId: 'cg-1', serviceType: 'PASEO', status: 'PENDING_PAYMENT',
  paidAt: null, paymentDeclaredAt: null, bookingGroupId: null, totalAmount: 100, sipQrId: null,
};

beforeEach(() => {
  jest.clearAllMocks();
  db.booking.updateMany.mockResolvedValue({ count: 1 });
  db.booking.update.mockResolvedValue({});
  db.booking.findUnique.mockResolvedValue({ bookingGroupId: null });
  db.user.update.mockResolvedValue({ balance: 140 });
  db.caregiverProfile.findUnique.mockResolvedValue({ userId: 'cg-user' });
});

describe('cancelar sin pagar con billetera puesta (pago combinado)', () => {
  it('devuelve la parte de billetera, con bloqueo, una sola vez, y lo dice en la notificación', async () => {
    db.booking.findFirst.mockResolvedValue({ ...unpaid, walletPaymentAmount: 40 });
    await cancelBooking('b1', 'client-1', 'cambié de idea', 'CLIENT_REQUEST', 'CAMBIO_DE_PLANES');

    const locks = db.$queryRaw.mock.calls.map((c) => String(c[0].join('?')));
    expect(locks.some((s) => s.includes('"users"') && s.includes('FOR UPDATE'))).toBe(true);
    expect(db.user.update).toHaveBeenCalledTimes(1);
    expect(db.user.update.mock.calls[0][0]).toEqual({
      where: { id: 'client-1' }, data: { balance: { increment: 40 } }, select: { balance: true },
    });
    expect(db.walletTransaction.create.mock.calls[0][0].data).toMatchObject({
      userId: 'client-1', type: 'REFUND', amount: 40, balance: 140, bookingId: 'b1', status: 'COMPLETED',
    });
    // Se deja en 0 para que ningún otro camino (job de QR, admin) la devuelva otra vez.
    expect(db.booking.update).toHaveBeenCalledWith({ where: { id: 'b1' }, data: { walletPaymentAmount: 0 } });
    const clientNotif = db.notification.create.mock.calls[0][0].data;
    expect(clientNotif.message).toMatch(/Bs 40\.00/);
    expect(clientNotif.message).not.toMatch(/No aplica reembolso/);
  });

  it('también al salir del pago o vencer el QR en la app (QR_ABANDONED)', async () => {
    db.booking.findFirst.mockResolvedValue({ ...unpaid, walletPaymentAmount: 25 });
    await cancelBooking('b1', 'client-1', 'QR vencido', 'QR_ABANDONED');
    expect(db.user.update.mock.calls[0][0].data).toEqual({ balance: { increment: 25 } });
  });

  it('sin billetera puesta no toca el saldo', async () => {
    db.booking.findFirst.mockResolvedValue({ ...unpaid, walletPaymentAmount: 0 });
    await cancelBooking('b1', 'client-1', 'x', 'CLIENT_REQUEST');
    expect(db.user.update).not.toHaveBeenCalled();
    expect(db.walletTransaction.create).not.toHaveBeenCalled();
  });

  it('si otra llamada ya la canceló (doble tap / job), no devuelve dos veces', async () => {
    db.booking.findFirst.mockResolvedValue({ ...unpaid, walletPaymentAmount: 40 });
    db.booking.updateMany.mockResolvedValue({ count: 0 });
    await expect(cancelBooking('b1', 'client-1', 'x', 'CLIENT_REQUEST')).rejects.toThrow(/ya está cancelada/);
    expect(db.user.update).not.toHaveBeenCalled();
  });
});
