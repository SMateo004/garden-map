/**
 * "Terminar servicio" bloquea la reserva antes de leer su estado. Sin el lock, dos
 * conclusiones simultáneas (doble toque, o dos empleados de una empresa) pasaban ambas
 * el chequeo de IN_PROGRESS y, con tiempo extra, cobraban y pagaban dos veces
 * (encontrado en las pruebas en vivo de empresa, 2026-10-17).
 */
import { concludeService } from '../../src/modules/booking-service/booking.service';
import prisma from '../../src/config/database';

jest.mock('../../src/config/database', () => {
  const db = {
    caregiverProfile: { findFirst: jest.fn() },
    booking: { findFirst: jest.fn(), update: jest.fn() },
    user: { update: jest.fn() },
    walletTransaction: { create: jest.fn() },
    notification: { create: jest.fn() },
    appSettings: { findUnique: jest.fn().mockResolvedValue(null), findMany: jest.fn().mockResolvedValue([]) },
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
jest.mock('../../src/services/notification.service', () => ({ onServiceCompleted: jest.fn().mockResolvedValue(undefined) }));
jest.mock('../../src/services/audit.service', () => ({ auditLog: jest.fn() }));
jest.mock('../../src/services/blockchain.service', () => ({ blockchainService: {} }));
jest.mock('../../src/services/chain-registry.service', () => ({ enqueueSafely: jest.fn() }));
jest.mock('../../src/shared/analytics', () => ({ track: jest.fn() }));
jest.mock('../../src/modules/referral/referral.service', () => ({
  grantReferralRewardIfEligible: jest.fn().mockResolvedValue(undefined),
}));

const db = prisma as unknown as {
  caregiverProfile: { findFirst: jest.Mock };
  booking: { findFirst: jest.Mock; update: jest.Mock };
  $queryRaw: jest.Mock;
};

it('bloquea la reserva (FOR UPDATE) antes de leer su estado', async () => {
  db.caregiverProfile.findFirst.mockResolvedValue({ id: 'cg-1', userId: 'owner-1' });
  db.booking.findFirst.mockResolvedValue({
    id: 'b1', clientId: 'c1', caregiverId: 'cg-1', status: 'IN_PROGRESS', serviceType: 'PASEO', pausedAt: null,
    serviceEvents: [{ type: 'PHOTO' }, { type: 'PHOTO' }], serviceTrackingData: [],
    serviceStartedAt: new Date(), duration: 30, totalAmount: 24, taxAmount: 0, petName: 'Toby',
  });
  db.booking.update.mockResolvedValue({ id: 'b1', status: 'COMPLETED', totalAmount: 24 });

  await concludeService('b1', 'owner-1', 'https://x/end.jpg', null, null);

  const lockCall = db.$queryRaw.mock.calls.findIndex((c) => String(c[0].join('?')).includes('"bookings"') && String(c[0].join('?')).includes('FOR UPDATE'));
  expect(lockCall).toBeGreaterThanOrEqual(0);
  const lockOrder = db.$queryRaw.mock.invocationCallOrder[lockCall]!;
  expect(lockOrder).toBeLessThan(db.booking.findFirst.mock.invocationCallOrder[0]!);
});

it('si al obtener el lock ya está terminada, no vuelve a cerrarla', async () => {
  db.caregiverProfile.findFirst.mockResolvedValue({ id: 'cg-1', userId: 'owner-1' });
  db.booking.findFirst.mockResolvedValue({ id: 'b1', caregiverId: 'cg-1', status: 'COMPLETED', serviceType: 'PASEO' });
  db.booking.update.mockClear();
  await expect(concludeService('b1', 'owner-1', 'https://x/end.jpg', null, null)).rejects.toThrow(/en curso/);
  expect(db.booking.update).not.toHaveBeenCalled();
});
