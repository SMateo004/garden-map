/**
 * Bajas de cuenta (auditorías 2026-10-11/12): ninguna baja procede con un servicio en curso,
 * reservas activas, disputas abiertas o un retiro en curso — y el retiro se revisa también dentro
 * de la transacción final, para que su saldo no se transfiera a GARDEN.
 */
import { assertNoDeletionBlockers, getDeletionBlockers } from '../../src/modules/auth/account-deletion.guard';
import { finalizeAccountDeletion } from '../../src/modules/auth/auth.service';
import prisma from '../../src/config/database';

jest.mock('../../src/config/database', () => {
  const db = {
    caregiverProfile: { findUnique: jest.fn(), update: jest.fn() },
    booking: { count: jest.fn() },
    dispute: { count: jest.fn() },
    walletTransaction: { count: jest.fn(), create: jest.fn() },
    user: { findUnique: jest.fn(), update: jest.fn() },
    refreshToken: { deleteMany: jest.fn(), updateMany: jest.fn() },
    $queryRaw: jest.fn().mockResolvedValue([]),
    $transaction: jest.fn(),
  };
  db.$transaction.mockImplementation((fn: (tx: unknown) => unknown) => fn(db));
  return { __esModule: true, default: db };
});
jest.mock('../../src/services/token-blacklist.service', () => ({ revokeUserSessions: jest.fn() }));

const db = prisma as unknown as {
  caregiverProfile: { findUnique: jest.Mock };
  booking: { count: jest.Mock };
  dispute: { count: jest.Mock };
  walletTransaction: { count: jest.Mock; create: jest.Mock };
  user: { findUnique: jest.Mock; update: jest.Mock };
};

function setCounts({ inProgress = 0, active = 0, disputes = 0, withdrawals = 0 } = {}) {
  db.caregiverProfile.findUnique.mockResolvedValue({ id: 'cg1' });
  db.booking.count.mockImplementation(({ where }: { where: { status: unknown } }) =>
    Promise.resolve(where.status === 'IN_PROGRESS' ? inProgress : active));
  db.dispute.count.mockResolvedValue(disputes);
  db.walletTransaction.count.mockResolvedValue(withdrawals);
}

beforeEach(() => jest.clearAllMocks());

describe('qué impide una baja', () => {
  it('sin nada pendiente, procede', async () => {
    setCounts();
    await expect(assertNoDeletionBlockers('u1')).resolves.toBeUndefined();
  });
  it('con una mascota a cargo (servicio en curso) no se aprueba', async () => {
    setCounts({ inProgress: 1, active: 1 });
    await expect(assertNoDeletionBlockers('u1', 'ALL', 'admin')).rejects.toMatchObject({ code: 'DELETION_SERVICE_IN_PROGRESS' });
  });
  it('con reservas activas', async () => {
    setCounts({ active: 2 });
    await expect(assertNoDeletionBlockers('u1')).rejects.toMatchObject({ code: 'PENDING_BOOKINGS' });
  });
  it('con una disputa abierta', async () => {
    setCounts({ disputes: 1 });
    await expect(assertNoDeletionBlockers('u1')).rejects.toMatchObject({ code: 'PENDING_DISPUTES' });
  });
  it('con un retiro en curso', async () => {
    setCounts({ withdrawals: 1 });
    await expect(assertNoDeletionBlockers('u1')).rejects.toMatchObject({ code: 'PENDING_WITHDRAWAL' });
  });
  it('dejar solo el perfil de cuidador no mira retiros ni reservas como dueño (la cuenta y el saldo siguen)', async () => {
    setCounts({ withdrawals: 1 });
    const b = await getDeletionBlockers('u1', 'CAREGIVER');
    expect(b.pendingWithdrawals).toBe(0);
    expect(b.activeAsClient).toBe(0);
    await expect(assertNoDeletionBlockers('u1', 'CAREGIVER')).resolves.toBeUndefined();
  });
});

describe('la baja final revisa el retiro con la fila bloqueada', () => {
  it('con un retiro en curso no transfiere el saldo a GARDEN', async () => {
    db.user.findUnique.mockResolvedValue({ id: 'u1', role: 'CLIENT', balance: 50 });
    db.walletTransaction.count.mockResolvedValue(1);
    await expect(finalizeAccountDeletion('u1')).rejects.toMatchObject({ code: 'PENDING_WITHDRAWAL' });
    expect(db.user.update).not.toHaveBeenCalled();
    expect(db.walletTransaction.create).not.toHaveBeenCalled();
  });
});
