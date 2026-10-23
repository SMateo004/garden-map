/**
 * Auditoría 2026-10-23: al cancelar TODA la reserva (no un viaje suelto) con un recojo/
 * entrega que no había empezado, el dinero se devolvía bien (va en el refundAmount único
 * de cancelBooking), pero booking.transportAmount/transportTaxAmount/transportRefundAmount
 * nunca se actualizaban — el resumen de pago seguía mostrando el viaje como "incluido" sin
 * reflejar la devolución. cancelLeg() sí lo hacía para un viaje cancelado suelto; ahora
 * settleTransportOnCancel() (dentro de cancelBooking) hace lo mismo.
 */
import { cancelBooking } from '../../src/modules/booking-service/booking.service';
import prisma from '../../src/config/database';

jest.mock('../../src/config/database', () => {
  const db = {
    booking: { findFirst: jest.fn(), findUnique: jest.fn(), count: jest.fn(), update: jest.fn(), updateMany: jest.fn() },
    user: { update: jest.fn() },
    walletTransaction: { create: jest.fn() },
    bookingTransportLeg: { findMany: jest.fn(), updateMany: jest.fn() },
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
  booking: { findFirst: jest.Mock; update: jest.Mock; updateMany: jest.Mock };
  bookingTransportLeg: { findMany: jest.Mock; updateMany: jest.Mock };
  user: { update: jest.Mock };
  walletTransaction: { create: jest.Mock };
  notification: { create: jest.Mock };
  caregiverProfile: { findUnique: jest.Mock };
};

const future = new Date(Date.now() + 240 * 60 * 60 * 1000); // 10 días: cae en el 100% de hospedaje

const paidBooking = {
  id: 'b1', clientId: 'client-1', caregiverId: 'cg-1', serviceType: 'HOSPEDAJE',
  status: 'CONFIRMED', paidAt: new Date(), paymentDeclaredAt: null, paymentAutoApprovedAt: null,
  bookingGroupId: null, totalAmount: 250, taxAmount: 0, walletPaymentAmount: 0, sipQrId: null,
  startDate: future, endDate: future, walkDate: null, timeSlot: null, duration: null,
  transportAmount: 50, transportTaxAmount: 0, transportRefundAmount: 0, petName: 'Toby',
};

const notStartedLeg = {
  id: 'leg-pickup', kind: 'PICKUP', status: 'SCHEDULED', fee: 50, tax: 0, trackingData: null,
};

beforeEach(() => {
  jest.clearAllMocks();
  db.booking.findFirst.mockResolvedValue({ ...paidBooking });
  db.booking.updateMany.mockResolvedValue({ count: 1 });
  db.booking.update.mockResolvedValue({});
  db.bookingTransportLeg.findMany.mockResolvedValue([{ ...notStartedLeg }]);
  db.bookingTransportLeg.updateMany.mockResolvedValue({ count: 1 });
  db.user.update.mockResolvedValue({ balance: 500 });
  db.caregiverProfile.findUnique.mockResolvedValue({ userId: 'cg-user' });
});

describe('cancelar toda la reserva con un recojo/entrega sin empezar', () => {
  it('descuenta transportAmount/transportTaxAmount y acredita transportRefundAmount, igual que cancelLeg', async () => {
    await cancelBooking('b1', 'client-1', 'cambié de idea', 'CLIENT_REQUEST', 'CAMBIO_DE_PLANES');

    const transportUpdate = db.booking.update.mock.calls.find(
      (c) => (c[0].data as Record<string, unknown>).transportRefundAmount !== undefined
    );
    expect(transportUpdate).toBeDefined();
    expect(transportUpdate![0]).toEqual({
      where: { id: 'b1' },
      data: {
        transportAmount: { decrement: 50 },
        transportTaxAmount: { decrement: 0 },
        transportRefundAmount: { increment: 50 },
      },
    });

    // El viaje queda cancelado y con su propio refundedAmount (lo que ya mostraba el
    // timeline del historial) — no debe romperse con este fix.
    expect(db.bookingTransportLeg.updateMany).toHaveBeenCalledWith({
      where: { id: 'leg-pickup', status: 'SCHEDULED' },
      data: expect.objectContaining({ status: 'CANCELLED', refundedAmount: expect.anything() }),
    });

    // El reembolso combinado (servicio 100% - Bs10 + transporte completo) sigue siendo uno
    // solo a la billetera del cliente — este fix no debe duplicarlo.
    expect(db.walletTransaction.create.mock.calls.filter((c) => c[0].data.type === 'REFUND')).toHaveLength(1);
    expect(db.walletTransaction.create.mock.calls.find((c) => c[0].data.type === 'REFUND')![0].data.amount).toBe(240);

    // Nadie le paga TRANSPORT_EARNING al cuidador: el viaje nunca empezó.
    expect(db.walletTransaction.create.mock.calls.some((c) => c[0].data.type === 'TRANSPORT_EARNING')).toBe(false);
  });

  it('un viaje ya en camino (con GPS) no se devuelve: se le paga al cuidador y no toca transportRefundAmount', async () => {
    db.bookingTransportLeg.findMany.mockResolvedValue([
      { ...notStartedLeg, status: 'EN_ROUTE', trackingData: [{ lat: -17.78, lng: -63.18 }] },
    ]);

    await cancelBooking('b1', 'client-1', 'cambié de idea', 'CLIENT_REQUEST', 'CAMBIO_DE_PLANES');

    const transportUpdate = db.booking.update.mock.calls.find(
      (c) => (c[0].data as Record<string, unknown>).transportRefundAmount !== undefined
    );
    expect(transportUpdate).toBeUndefined();

    const earning = db.walletTransaction.create.mock.calls.find((c) => c[0].data.type === 'TRANSPORT_EARNING');
    expect(earning).toBeDefined();
    expect(earning![0].data.amount).toBe(50);
    expect(earning![0].data.userId).toBe('cg-user');

    // El servicio (sin el transporte, que ya se le pagó al cuidador) sigue reembolsándose
    // completo al dueño: 100% de 200 - Bs10 de la política de hospedaje.
    const refund = db.walletTransaction.create.mock.calls.find((c) => c[0].data.type === 'REFUND');
    expect(refund![0].data.amount).toBe(190);
  });
});
