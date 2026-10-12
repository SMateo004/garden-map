/**
 * Eliminar cuentas desde el panel admin (deleteUserAccountByAdmin): misma baja
 * que la de la app, pero sin quedarse con el saldo de nadie — se bloquea si
 * hay reservas activas, saldo a favor o un retiro en curso. Y una cuenta
 * eliminada deja de poder usar sus tokens (isUserRevoked).
 */
import prisma from '../../src/config/database';
import { deleteUserAccountByAdmin } from '../../src/modules/admin/admin.service';
import { isUserRevoked, revokeUserSessions } from '../../src/services/token-blacklist.service';
import * as authService from '../../src/modules/auth/auth.service';

jest.mock('../../src/config/database', () => ({
  __esModule: true,
  default: {
    user: { findUnique: jest.fn() },
    booking: { count: jest.fn() },
    walletTransaction: { count: jest.fn() },
    adminAction: { create: jest.fn().mockResolvedValue({}) },
  },
}));
jest.mock('../../src/modules/auth/auth.service', () => ({
  comparePassword: jest.fn().mockResolvedValue(true),
  finalizeAccountDeletion: jest.fn().mockResolvedValue(undefined),
}));
jest.mock('../../src/shared/cache', () => ({
  getCache: () => ({ del: jest.fn().mockResolvedValue(undefined) }),
  delByPrefix: jest.fn().mockResolvedValue(undefined),
  caregiverDetailCacheKey: (id: string) => `caregivers:detail:${id}`,
}));
jest.mock('../../src/services/firebase.service', () => ({
  sendPushToUser: jest.fn().mockResolvedValue(undefined),
  sendPushToAdmins: jest.fn().mockResolvedValue(undefined),
}));
jest.mock('../../src/shared/analytics', () => ({ track: jest.fn(), identify: jest.fn() }));

const db = prisma as unknown as {
  user: { findUnique: jest.Mock };
  booking: { count: jest.Mock };
  walletTransaction: { count: jest.Mock };
  adminAction: { create: jest.Mock };
};
const finalize = authService.finalizeAccountDeletion as jest.Mock;
const body = { reason: 'Perfil falso confirmado', adminPassword: 'x' };

function target(over: Record<string, unknown> = {}) {
  return { role: 'CLIENT', isDeleted: false, balance: 0, caregiverProfile: null, ...over };
}

/** 1ª llamada: el admin (contraseña); 2ª: la cuenta a eliminar. */
function users(t: unknown) {
  db.user.findUnique.mockResolvedValueOnce({ id: 'admin', passwordHash: 'h' }).mockResolvedValueOnce(t);
}

describe('deleteUserAccountByAdmin', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    db.booking.count.mockResolvedValue(0);
    db.walletTransaction.count.mockResolvedValue(0);
  });

  it('elimina un dueño sin pendientes y deja constancia', async () => {
    users(target());
    await deleteUserAccountByAdmin('u1', 'admin', body);
    expect(finalize).toHaveBeenCalledWith('u1');
    expect(db.adminAction.create).toHaveBeenCalledWith({
      data: expect.objectContaining({ actionType: 'USER_DELETE', targetId: 'u1', notes: body.reason }),
    });
  });

  it('revisa también las reservas como cuidador', async () => {
    users(target({ role: 'CAREGIVER', caregiverProfile: { id: 'cp1' } }));
    await deleteUserAccountByAdmin('u1', 'admin', body);
    const where = db.booking.count.mock.calls[0][0].where;
    expect(where.OR).toEqual([{ clientId: 'u1' }, { caregiverId: 'cp1' }]);
  });

  it.each([
    ['reservas activas', () => db.booking.count.mockResolvedValue(2), /2 reservas activas/],
    ['un retiro en curso', () => db.walletTransaction.count.mockResolvedValue(1), /retiro en curso/],
  ])('no elimina si tiene %s', async (_label, setup, msg) => {
    users(target());
    setup();
    await expect(deleteUserAccountByAdmin('u1', 'admin', body)).rejects.toThrow(msg);
    expect(finalize).not.toHaveBeenCalled();
  });

  it('no se queda con el saldo a favor', async () => {
    users(target({ balance: 45.5 }));
    await expect(deleteUserAccountByAdmin('u1', 'admin', body)).rejects.toThrow(/Bs 45\.50 a favor/);
    expect(finalize).not.toHaveBeenCalled();
  });

  it('no elimina admins ni la propia cuenta', async () => {
    users(target({ role: 'ADMIN' }));
    await expect(deleteUserAccountByAdmin('u2', 'admin', body)).rejects.toThrow(/administrador/);
    db.user.findUnique.mockResolvedValueOnce({ id: 'admin', passwordHash: 'h' });
    await expect(deleteUserAccountByAdmin('admin', 'admin', body)).rejects.toThrow(/propia cuenta/);
    expect(finalize).not.toHaveBeenCalled();
  });

  it('exige motivo', async () => {
    await expect(deleteUserAccountByAdmin('u1', 'admin', { ...body, reason: 'x' })).rejects.toThrow(/motivo/);
  });
});

describe('isUserRevoked', () => {
  beforeEach(() => jest.clearAllMocks());

  it('una cuenta eliminada no puede seguir usando sus tokens', async () => {
    db.user.findUnique.mockResolvedValueOnce({ isDeleted: true });
    expect(await isUserRevoked('gone-1')).toBe(true);
  });

  it('una cuenta activa sí, y se consulta la base una sola vez (caché)', async () => {
    db.user.findUnique.mockResolvedValueOnce({ isDeleted: false });
    expect(await isUserRevoked('ok-1')).toBe(false);
    expect(await isUserRevoked('ok-1')).toBe(false);
    expect(db.user.findUnique).toHaveBeenCalledTimes(1);
  });

  it('al eliminar, el bloqueo es inmediato aunque estuviera en caché como activa', async () => {
    db.user.findUnique.mockResolvedValueOnce({ isDeleted: false });
    expect(await isUserRevoked('ok-2')).toBe(false);
    revokeUserSessions('ok-2');
    expect(await isUserRevoked('ok-2')).toBe(true);
  });

  it('si la base falla, no bloquea', async () => {
    db.user.findUnique.mockRejectedValueOnce(new Error('db caída'));
    expect(await isUserRevoked('x-1')).toBe(false);
  });
});
