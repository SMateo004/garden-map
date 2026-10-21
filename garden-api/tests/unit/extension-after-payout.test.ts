/**
 * Aprobar una extensión después de que al cuidador ya se le liberó el pago:
 * antes el total subía pero el cuidador nunca recibía ese extra (el dueño sí
 * lo pagó). Ahora se le acredita su neto en ese momento. Y una reserva
 * cancelada no acepta aprobar la extensión.
 */
import prisma from '../../src/config/database';
import { approveExtensionPayment } from '../../src/modules/admin/admin.service';

jest.mock('../../src/config/database', () => {
  const db: any = {
    booking: { findUnique: jest.fn(), update: jest.fn().mockResolvedValue({}) },
    user: { update: jest.fn().mockResolvedValue({ balance: 150 }) },
    walletTransaction: { create: jest.fn().mockResolvedValue({}) },
    adminNotification: { updateMany: jest.fn().mockResolvedValue({ count: 0 }) },
    notification: { create: jest.fn().mockResolvedValue({}) },
    $queryRaw: jest.fn().mockResolvedValue([]),
    $transaction: jest.fn(),
  };
  db.$transaction.mockImplementation((fn: (tx: unknown) => unknown) => fn(db));
  return { __esModule: true, default: db };
});
jest.mock('../../src/modules/pricing/pricing.service', () => ({
  getCommissionRate: jest.fn().mockResolvedValue(0.1),
  caregiverUnitFromPriced: jest.fn((p: number) => p / 1.1),
  getTaxRate: jest.fn().mockResolvedValue(0),
  caregiverNetOf: jest.fn(),
  normalizePayer: (v: unknown) => (v === 'CAREGIVER' ? 'CAREGIVER' : 'CLIENT'),
}));
jest.mock('../../src/services/chain-registry.service', () => ({
  enqueueBookingExtension: jest.fn().mockResolvedValue(undefined),
  enqueueBookingCreate: jest.fn(),
  enqueueSafely: jest.fn(),
  enqueueDisputeResolution: jest.fn(),
  disputeAmounts: jest.fn(),
}));
jest.mock('../../src/services/firebase.service', () => ({ sendPushToUser: jest.fn().mockResolvedValue(undefined), sendPushToAdmins: jest.fn() }));
jest.mock('../../src/shared/cache', () => ({ getCache: () => ({ del: jest.fn() }), delByPrefix: jest.fn(), caregiverDetailCacheKey: (id: string) => id }));
jest.mock('../../src/shared/analytics', () => ({ track: jest.fn(), identify: jest.fn() }));
jest.mock('../../src/services/notification.service', () => ({}));

const db = prisma as any;
const pendingExt = {
  type: 'EXTENSION_PENDING_PAYMENT', extensionId: 'e1', additionalMinutes: 30,
  extraAmount: 22, extraCommission: 2, extraTax: 0, method: 'manual',
};
const booking = (over: Record<string, unknown> = {}) => ({
  id: 'b1', clientId: 'c1', serviceType: 'PASEO', status: 'COMPLETED', payoutStatus: 'PAID',
  caregiverId: 'cp1', caregiver: { userId: 'cg1' }, totalAmount: 44, commissionAmount: 4, taxAmount: 0,
  pricePerUnit: 44, duration: 60, serviceEvents: [pendingExt], ...over,
});

describe('approveExtensionPayment', () => {
  beforeEach(() => jest.clearAllMocks());

  it('si al cuidador ya se le pagó, le acredita el neto de la extensión', async () => {
    db.booking.findUnique.mockResolvedValue(booking());
    await approveExtensionPayment('b1', 'e1', 'admin');
    expect(db.user.update).toHaveBeenCalledWith(expect.objectContaining({ where: { id: 'cg1' }, data: { balance: { increment: 20 } } }));
    expect(db.walletTransaction.create).toHaveBeenCalledWith({
      data: expect.objectContaining({ userId: 'cg1', type: 'EARNING', amount: 20, bookingId: 'b1' }),
    });
  });

  it('si el pago todavía no se liberó, no acredita nada (entra en el pago normal)', async () => {
    db.booking.findUnique.mockResolvedValue(booking({ status: 'IN_PROGRESS', payoutStatus: 'PENDING' }));
    await approveExtensionPayment('b1', 'e1', 'admin');
    expect(db.user.update).not.toHaveBeenCalled();
    expect(db.booking.update).toHaveBeenCalled();
  });

  it('una reserva cancelada no acepta aprobar la extensión', async () => {
    db.booking.findUnique.mockResolvedValue(booking({ status: 'CANCELLED', payoutStatus: 'PENDING' }));
    await expect(approveExtensionPayment('b1', 'e1', 'admin')).rejects.toThrow(/cancelada/);
    expect(db.booking.update).not.toHaveBeenCalled();
  });
});
