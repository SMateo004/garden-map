/**
 * Propina al cuidador: en curso o terminado, una sola vez, aunque no alcance
 * el saldo (queda deuda). Al cuidador le llega ya lo que el saldo cubría; el
 * resto queda "por cobrar" y se libera cuando el dueño salda la deuda.
 */
import { addTip } from '../../src/modules/booking-service/booking.service';
import { releasePendingTips } from '../../src/modules/booking-service/tip-release.service';
import prisma from '../../src/config/database';

jest.mock('../../src/config/database', () => {
  const db = {
    booking: { findFirst: jest.fn(), findMany: jest.fn(), updateMany: jest.fn() },
    user: { findUnique: jest.fn(), update: jest.fn() },
    walletTransaction: {
      create: jest.fn(), aggregate: jest.fn(), findMany: jest.fn(), updateMany: jest.fn(), update: jest.fn(),
    },
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
jest.mock('../../src/services/socket.service', () => ({ emitWalletUpdated: jest.fn(), getIO: jest.fn() }));
jest.mock('../../src/services/notification.service', () => ({}));
jest.mock('../../src/services/audit.service', () => ({ auditLog: jest.fn() }));
jest.mock('../../src/services/blockchain.service', () => ({ blockchainService: {} }));
jest.mock('../../src/services/chain-registry.service', () => ({ enqueueSafely: jest.fn() }));
jest.mock('../../src/shared/analytics', () => ({ track: jest.fn() }));

const db = prisma as unknown as {
  booking: { findFirst: jest.Mock; findMany: jest.Mock; updateMany: jest.Mock };
  user: { findUnique: jest.Mock; update: jest.Mock };
  walletTransaction: { create: jest.Mock; aggregate: jest.Mock; findMany: jest.Mock; updateMany: jest.Mock; update: jest.Mock };
  $queryRaw: jest.Mock;
};

const booking = (status: string, tipAmount: number | null = null) => ({
  id: 'booking-123456', clientId: 'client-1', status, tipAmount, caregiver: { userId: 'cg-user' },
});

function setBalance(clientBalance: number) {
  db.user.findUnique.mockResolvedValue({ balance: clientBalance });
  db.walletTransaction.aggregate.mockResolvedValue({ _sum: { amount: 0 } });
  db.user.update.mockImplementation(({ where, data }) => {
    const base = where.id === 'client-1' ? clientBalance : 100;
    const d = data.balance.increment ?? -data.balance.decrement;
    return Promise.resolve({ balance: base + d });
  });
}

beforeEach(() => {
  jest.clearAllMocks();
  db.booking.updateMany.mockResolvedValue({ count: 1 });
});

describe('addTip', () => {
  it('con saldo suficiente: todo llega al cuidador al instante', async () => {
    db.booking.findFirst.mockResolvedValue(booking('IN_PROGRESS'));
    setBalance(50);
    const r = await addTip('booking-123456', 'client-1', 20);

    expect(r).toMatchObject({ tipAmount: 20, balance: 30, paidNow: 20, pendingAmount: 0 });
    const rows = db.walletTransaction.create.mock.calls.map((c) => c[0].data);
    expect(rows).toEqual([
      expect.objectContaining({ userId: 'client-1', type: 'TIP', amount: 20, status: 'COMPLETED' }),
      expect.objectContaining({ userId: 'cg-user', type: 'TIP_RECEIVED', amount: 20, status: 'COMPLETED' }),
    ]);
    const locks = db.$queryRaw.mock.calls.map((c) => String(c[0].join('?')));
    expect(locks.some((s) => s.includes('"bookings"') && s.includes('FOR UPDATE'))).toBe(true);
    expect(locks.some((s) => s.includes('"users"') && s.includes('FOR UPDATE'))).toBe(true);
  });

  it('sin saldo: el dueño queda en negativo y la propina queda por cobrar', async () => {
    db.booking.findFirst.mockResolvedValue(booking('COMPLETED'));
    setBalance(5);
    const r = await addTip('booking-123456', 'client-1', 20);

    expect(r).toMatchObject({ balance: -15, paidNow: 5, pendingAmount: 15 });
    const rows = db.walletTransaction.create.mock.calls.map((c) => c[0].data);
    expect(rows[0]).toMatchObject({ userId: 'client-1', type: 'TIP', amount: 20, balance: -15 });
    expect(rows[0].description).toMatch(/Bs 15\.00 se cobran en tu próxima reserva/);
    expect(rows[1]).toMatchObject({ userId: 'cg-user', type: 'TIP_RECEIVED', amount: 5, status: 'COMPLETED' });
    expect(rows[2]).toMatchObject({ userId: 'cg-user', type: 'TIP_RECEIVED', amount: 15, status: 'PENDING' });
    // Al cuidador solo se le suman los Bs 5 cubiertos.
    const cg = db.user.update.mock.calls.filter((c) => c[0].where.id === 'cg-user');
    expect(cg).toHaveLength(1);
    expect(cg[0][0].data).toEqual({ balance: { increment: 5 } });
  });

  it('una sola vez por reserva', async () => {
    db.booking.findFirst.mockResolvedValue(booking('COMPLETED', 10));
    await expect(addTip('booking-123456', 'client-1', 5)).rejects.toMatchObject({ code: 'TIP_ALREADY_GIVEN' });
  });

  it('no antes de que empiece el servicio', async () => {
    db.booking.findFirst.mockResolvedValue(booking('CONFIRMED'));
    await expect(addTip('booking-123456', 'client-1', 5)).rejects.toMatchObject({ code: 'BOOKING_NOT_TIPPABLE' });
  });
});

describe('releasePendingTips', () => {
  const pending = (id: string, amount: number) => ({
    id, userId: 'cg-user', amount, bookingId: 'booking-123456', createdAt: new Date(),
  });

  beforeEach(() => {
    db.booking.findMany.mockResolvedValue([{ id: 'booking-123456' }]);
    db.walletTransaction.updateMany.mockResolvedValue({ count: 1 });
    db.user.update.mockResolvedValue({ balance: 115 });
  });

  it('con la deuda saldada libera la propina al cuidador', async () => {
    db.user.findUnique.mockResolvedValue({ balance: 0 });
    db.walletTransaction.findMany.mockResolvedValue([pending('t1', 15)]);
    const released = await releasePendingTips(db as never, 'client-1');

    expect(released).toBe(15);
    expect(db.user.update).toHaveBeenCalledWith({
      where: { id: 'cg-user' }, data: { balance: { increment: 15 } }, select: { balance: true },
    });
    expect(db.walletTransaction.updateMany.mock.calls[0][0].where).toEqual({ id: 't1', status: 'PENDING' });
  });

  it('mientras la deuda siga cubriendo la propina, no libera nada', async () => {
    db.user.findUnique.mockResolvedValue({ balance: -15 });
    db.walletTransaction.findMany.mockResolvedValue([pending('t1', 15)]);
    expect(await releasePendingTips(db as never, 'client-1')).toBe(0);
    expect(db.user.update).not.toHaveBeenCalled();
  });

  it('si otra liberación ya la tomó, no acredita dos veces', async () => {
    db.user.findUnique.mockResolvedValue({ balance: 10 });
    db.walletTransaction.findMany.mockResolvedValue([pending('t1', 15)]);
    db.walletTransaction.updateMany.mockResolvedValue({ count: 0 });
    expect(await releasePendingTips(db as never, 'client-1')).toBe(0);
    expect(db.user.update).not.toHaveBeenCalled();
  });
});
