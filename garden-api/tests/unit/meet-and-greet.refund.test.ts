/**
 * Meet & Greet con incompatibilidad: la reserva (ya pagada) se cancela y el
 * total vuelve 100% automático a la billetera del cliente, en la misma
 * transacción. Antes se cancelaba sin devolver nada.
 */

import { complete } from '../../src/modules/meet-and-greet/meet-and-greet.service';
import prisma from '../../src/config/database';

const tx = {
  meetAndGreet: { updateMany: jest.fn(), findUnique: jest.fn() },
  booking: { updateMany: jest.fn(), update: jest.fn() },
  user: { update: jest.fn() },
  walletTransaction: { create: jest.fn() },
};

jest.mock('../../src/config/database', () => ({
  __esModule: true,
  default: {
    booking: { findUnique: jest.fn() },
    notification: { create: jest.fn().mockResolvedValue({}) },
    chatMessage: { create: jest.fn().mockResolvedValue({ id: 'm1', bookingId: 'b1', createdAt: new Date() }) },
    $transaction: jest.fn(),
  },
}));

jest.mock('../../src/services/socket.service', () => ({ getIO: () => null }));
jest.mock('../../src/services/chain-registry.service', () => ({
  enqueueBookingCancel: jest.fn().mockResolvedValue(undefined),
  enqueueSafely: jest.fn((_label: string, fn: () => Promise<void>) => { void fn(); }),
}));
const chain = jest.requireMock('../../src/services/chain-registry.service') as { enqueueBookingCancel: jest.Mock };

const mockPrisma = prisma as any;

const paidBooking = {
  id: 'b1',
  clientId: 'client-1',
  status: 'WAITING_CAREGIVER_APPROVAL',
  paidAt: new Date(),
  totalAmount: 128,
  meetAndGreet: { status: 'ACCEPTED' },
  caregiver: { userId: 'cg-user' },
};

beforeEach(() => {
  jest.clearAllMocks();
  mockPrisma.$transaction.mockImplementation((fn: any) => fn(tx));
  mockPrisma.booking.findUnique.mockResolvedValue(paidBooking);
  tx.meetAndGreet.updateMany.mockResolvedValue({ count: 1 });
  tx.meetAndGreet.findUnique.mockResolvedValue({ bookingId: 'b1', status: 'COMPLETED' });
  tx.booking.updateMany.mockResolvedValue({ count: 1 });
  tx.user.update.mockResolvedValue({ balance: 128 });
});

describe('Meet & Greet complete()', () => {
  it('incompatibilidad: cancela y reembolsa el 100% a la billetera', async () => {
    await complete('b1', 'cg-user', { approved: false });

    expect(tx.booking.updateMany).toHaveBeenCalledWith(expect.objectContaining({
      where: { id: 'b1', status: { in: ['WAITING_CAREGIVER_APPROVAL', 'PENDING_MG'] } },
      data: expect.objectContaining({ status: 'CANCELLED', refundStatus: 'APPROVED', refundAmount: 128 }),
    }));
    expect(tx.user.update).toHaveBeenCalledWith(expect.objectContaining({
      where: { id: 'client-1' },
      data: { balance: { increment: 128 } },
    }));
    expect(tx.walletTransaction.create).toHaveBeenCalledWith(expect.objectContaining({
      data: expect.objectContaining({ type: 'REFUND', amount: 128, balance: 128, userId: 'client-1' }),
    }));
    expect(chain.enqueueBookingCancel).toHaveBeenCalledWith('b1');
  });

  it('Meet & Greet antes de pagar (PENDING_MG): se cancela sin reembolso ni registro on-chain', async () => {
    mockPrisma.booking.findUnique.mockResolvedValue({ ...paidBooking, status: 'PENDING_MG', paidAt: null });
    await complete('b1', 'cg-user', { approved: false });
    const call = tx.booking.updateMany.mock.calls[0][0];
    expect(call.data.status).toBe('CANCELLED');
    expect(call.data.refundAmount).toBeUndefined();
    expect(tx.user.update).not.toHaveBeenCalled();
    expect(tx.walletTransaction.create).not.toHaveBeenCalled();
    expect(chain.enqueueBookingCancel).not.toHaveBeenCalled();
  });

  it('compatible: no cancela ni mueve dinero', async () => {
    await complete('b1', 'cg-user', { approved: true });
    expect(tx.booking.updateMany).not.toHaveBeenCalled();
    expect(tx.user.update).not.toHaveBeenCalled();
  });

  it('doble envío: el segundo no reembolsa otra vez', async () => {
    tx.meetAndGreet.updateMany.mockResolvedValue({ count: 0 });
    await expect(complete('b1', 'cg-user', { approved: false })).rejects.toThrow();
    expect(tx.user.update).not.toHaveBeenCalled();
  });

  it('la reserva ya no espera al cuidador (cliente canceló antes): no reembolsa', async () => {
    tx.booking.updateMany.mockResolvedValue({ count: 0 });
    await expect(complete('b1', 'cg-user', { approved: false })).rejects.toThrow();
    expect(tx.user.update).not.toHaveBeenCalled();
  });
});
