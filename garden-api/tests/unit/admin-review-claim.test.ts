/**
 * Antecedentes y NIT (auditoría 2026-10-16, H1): una decisión del admin solo vale si el documento
 * sigue en revisión — dos admins no deciden cosas opuestas, y no se suspende a alguien ya aprobado.
 */
import prisma from '../../src/config/database';
import * as admin from '../../src/modules/admin/admin.service';

jest.mock('../../src/config/database', () => {
  const db: any = {
    caregiverProfile: { findUnique: jest.fn().mockResolvedValue({ userId: 'u1' }), updateMany: jest.fn() },
    notification: { create: jest.fn() },
    adminAction: { create: jest.fn() },
    $queryRaw: jest.fn().mockResolvedValue([]),
    $transaction: jest.fn(),
  };
  db.$transaction.mockImplementation((fn: (tx: unknown) => unknown) => fn(db));
  return { __esModule: true, default: db };
});
jest.mock('../../src/services/chain-registry.service', () => ({
  enqueueBookingCreate: jest.fn(), enqueueSafely: jest.fn(), enqueueBookingExtension: jest.fn(),
  enqueueDisputeResolution: jest.fn(), disputeAmounts: jest.fn(),
}));
jest.mock('../../src/services/firebase.service', () => ({ sendPushToUser: jest.fn().mockResolvedValue(undefined), sendPushToAdmins: jest.fn() }));
jest.mock('../../src/shared/cache', () => ({ getCache: () => ({ del: jest.fn() }), delByPrefix: jest.fn(), caregiverDetailCacheKey: (id: string) => id }));
jest.mock('../../src/shared/analytics', () => ({ track: jest.fn(), identify: jest.fn() }));
jest.mock('../../src/services/notification.service', () => ({}));

const db = prisma as any;
beforeEach(() => jest.clearAllMocks());

it.each([
  ['rechazar antecedentes', () => admin.rejectAntecedentesDocument('p1', 'a1', 'borroso')],
  ['aprobar NIT', () => admin.approveNitVerification('p1', 'a1')],
  ['rechazar NIT', () => admin.rejectNitVerification('p1', 'a1', 'vencido')],
  ['suspender por antecedentes', () => admin.suspendForAntecedentes('p1', 'a1')],
])('%s: si otro admin ya decidió, falla sin avisar ni auditar', async (_n, run) => {
  db.caregiverProfile.updateMany.mockResolvedValue({ count: 0 });
  await expect(run()).rejects.toThrow(/ya no está en revisión/);
  expect(db.notification.create).not.toHaveBeenCalled();
  expect(db.adminAction.create).not.toHaveBeenCalled();
  expect(db.caregiverProfile.updateMany.mock.calls[0][0].where).toMatchObject({ id: 'p1' });
});

it('aprobar NIT en revisión avisa y audita una vez', async () => {
  db.caregiverProfile.updateMany.mockResolvedValue({ count: 1 });
  await admin.approveNitVerification('p1', 'a1');
  expect(db.caregiverProfile.updateMany.mock.calls[0][0].where).toEqual({ id: 'p1', nitStatus: 'EN_REVISION' });
  expect(db.notification.create).toHaveBeenCalledTimes(1);
  expect(db.adminAction.create).toHaveBeenCalledTimes(1);
});
