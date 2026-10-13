/**
 * Toda confirmación de pago (banco, botón "Aprobar" del admin, aprobación
 * segura o automática) registra la donación y salda la deuda previa incluida
 * en el QR — antes el botón del admin no hacía ninguna de las dos y la
 * aprobación automática no saldaba la deuda.
 */
import prisma from '../../src/config/database';
import { applyConfirmedPaymentEffects } from '../../src/modules/payment-service/payment.service';

jest.mock('../../src/config/database', () => {
  const db: any = {
    booking: { findUnique: jest.fn() },
    donation: { upsert: jest.fn().mockResolvedValue({}) },
    walletTransaction: { count: jest.fn().mockResolvedValue(0), create: jest.fn().mockResolvedValue({}) },
    user: { findUnique: jest.fn(), update: jest.fn() },
    $queryRaw: jest.fn().mockResolvedValue([]),
    $transaction: jest.fn(),
  };
  db.$transaction.mockImplementation((fn: (tx: unknown) => unknown) => fn(db));
  return { __esModule: true, default: db };
});
jest.mock('../../src/services/firebase.service', () => ({ sendPushToUser: jest.fn(), sendPushToAdmins: jest.fn() }));
jest.mock('../../src/services/notification.service', () => ({}));
jest.mock('../../src/services/blockchain.service', () => ({ blockchainService: {} }));
jest.mock('../../src/services/chain-registry.service', () => ({ enqueueBookingCreate: jest.fn(), enqueueSafely: jest.fn() }));
jest.mock('../../src/shared/analytics', () => ({ track: jest.fn() }));

const db = prisma as any;
const booking = (over: Record<string, unknown> = {}) => ({ id: 'b1', clientId: 'c1', donationAmount: null, debtRecoveryAmount: 0, ...over });

describe('applyConfirmedPaymentEffects', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    db.walletTransaction.count.mockResolvedValue(0);
  });

  it('registra la donación', async () => {
    db.booking.findUnique.mockResolvedValue(booking({ donationAmount: 10 }));
    await applyConfirmedPaymentEffects('b1');
    expect(db.donation.upsert).toHaveBeenCalledWith({
      where: { bookingId: 'b1' },
      create: { bookingId: 'b1', clientId: 'c1', amount: 10 },
      update: {},
    });
  });

  it('salda la deuda incluida en el QR', async () => {
    db.booking.findUnique.mockResolvedValue(booking({ debtRecoveryAmount: 20 }));
    db.user.findUnique.mockResolvedValue({ balance: -20 });
    db.user.update.mockResolvedValue({ balance: 0 });
    await applyConfirmedPaymentEffects('b1');
    expect(db.user.update).toHaveBeenCalledWith(expect.objectContaining({ data: { balance: { increment: 20 } } }));
    expect(db.walletTransaction.create).toHaveBeenCalledWith({
      data: expect.objectContaining({ type: 'DEBT_RECOVERY', amount: 20, balance: 0, bookingId: 'b1' }),
    });
  });

  it('nunca recupera más que la deuda vigente', async () => {
    db.booking.findUnique.mockResolvedValue(booking({ debtRecoveryAmount: 20 }));
    db.user.findUnique.mockResolvedValue({ balance: -5 });
    db.user.update.mockResolvedValue({ balance: 0 });
    await applyConfirmedPaymentEffects('b1');
    expect(db.user.update).toHaveBeenCalledWith(expect.objectContaining({ data: { balance: { increment: 5 } } }));
  });

  it('no la salda dos veces para la misma reserva', async () => {
    db.booking.findUnique.mockResolvedValue(booking({ debtRecoveryAmount: 20 }));
    db.walletTransaction.count.mockResolvedValue(1);
    await applyConfirmedPaymentEffects('b1');
    expect(db.user.update).not.toHaveBeenCalled();
  });

  it('sin donación ni deuda no hace nada', async () => {
    db.booking.findUnique.mockResolvedValue(booking());
    await applyConfirmedPaymentEffects('b1');
    expect(db.donation.upsert).not.toHaveBeenCalled();
    expect(db.$transaction).not.toHaveBeenCalled();
  });
});
