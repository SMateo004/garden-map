/**
 * Aprobar un pago reclama la reserva de forma atómica (auditoría 2026-10-14, H2): si la
 * aprobación automática u otro admin ya la aprobó entre la lectura y la escritura, no se repiten
 * la auditoría, la notificación al cuidador ni los efectos del pago.
 */
import prisma from '../../src/config/database';
import { approvePaymentSecure } from '../../src/modules/admin/admin.service';

jest.mock('../../src/config/database', () => {
  const db: any = {
    user: { findUnique: jest.fn().mockResolvedValue({ id: 'a1', passwordHash: 'h' }) },
    booking: { findUnique: jest.fn(), updateMany: jest.fn() },
    caregiverProfile: { findUnique: jest.fn().mockResolvedValue({ userId: 'cg1' }) },
    adminAction: { create: jest.fn() },
    notification: { create: jest.fn() },
    $queryRaw: jest.fn().mockResolvedValue([]),
    $transaction: jest.fn(),
  };
  db.$transaction.mockImplementation((fn: (tx: unknown) => unknown) => fn(db));
  return { __esModule: true, default: db };
});
jest.mock('../../src/modules/auth/auth.service', () => ({ comparePassword: jest.fn().mockResolvedValue(true) }));
jest.mock('../../src/modules/booking-service/booking-group.service', () => ({
  revertGroupSiblingsToPending: jest.fn(),
  markGroupSiblingsPaid: jest.fn().mockResolvedValue([]),
  afterGroupSiblingsPaid: jest.fn(),
}));
jest.mock('../../src/modules/payment-service/payment.service', () => ({ applyConfirmedPaymentEffects: jest.fn() }));
jest.mock('../../src/services/chain-registry.service', () => ({
  enqueueBookingCreate: jest.fn(), enqueueSafely: jest.fn(), enqueueBookingExtension: jest.fn(),
  enqueueDisputeResolution: jest.fn(), disputeAmounts: jest.fn(),
}));
jest.mock('../../src/services/firebase.service', () => ({ sendPushToUser: jest.fn().mockResolvedValue(undefined), sendPushToAdmins: jest.fn() }));
jest.mock('../../src/shared/cache', () => ({ getCache: () => ({ del: jest.fn() }), delByPrefix: jest.fn(), caregiverDetailCacheKey: (id: string) => id }));
jest.mock('../../src/shared/analytics', () => ({ track: jest.fn(), identify: jest.fn() }));
jest.mock('../../src/services/notification.service', () => ({}));

const db = prisma as any;
const { applyConfirmedPaymentEffects } = jest.requireMock('../../src/modules/payment-service/payment.service');

beforeEach(() => {
  jest.clearAllMocks();
  db.booking.findUnique.mockResolvedValue({
    id: 'b1', clientId: 'c1', caregiverId: 'cp1', status: 'PAYMENT_PENDING_APPROVAL',
    paymentApprovalRequestedAt: new Date(Date.now() - 60_000),
  });
});

it('reclama la reserva solo si sigue pendiente de pago', async () => {
  db.booking.updateMany.mockResolvedValue({ count: 1 });
  await approvePaymentSecure('b1', 'a1', 'pw');
  expect(db.booking.updateMany).toHaveBeenCalledWith(expect.objectContaining({
    where: { id: 'b1', status: { in: ['PAYMENT_PENDING_APPROVAL', 'PENDING_PAYMENT'] } },
  }));
  expect(db.adminAction.create).toHaveBeenCalledTimes(1);
  expect(applyConfirmedPaymentEffects).toHaveBeenCalledWith('b1');
});

it('si otro camino ya la aprobó, responde conflicto y no repite nada', async () => {
  db.booking.updateMany.mockResolvedValue({ count: 0 });
  await expect(approvePaymentSecure('b1', 'a1', 'pw')).rejects.toMatchObject({ statusCode: 409 });
  expect(db.adminAction.create).not.toHaveBeenCalled();
  expect(db.notification.create).not.toHaveBeenCalled();
  expect(applyConfirmedPaymentEffects).not.toHaveBeenCalled();
});
