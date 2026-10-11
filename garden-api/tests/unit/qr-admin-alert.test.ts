/**
 * Cuando un cliente genera el QR de pago, los admins quedan al tanto sin esperar a que el
 * cliente avise que pagó: se deja un aviso en la campana (mismo tipo que el pedido de
 * aprobación manual) y la reserva ya figura en "Pagos por aprobar". Si el cliente regenera el
 * QR varias veces seguidas no se duplica el aviso.
 */
import { recordQrRequestedForAdmins } from '../../src/modules/booking-service/booking.service';

jest.mock('../../src/config/database', () => ({ __esModule: true, default: {} }));
jest.mock('../../src/services/firebase.service', () => ({
  sendPushToUser: jest.fn().mockResolvedValue(undefined),
  sendPushToAdmins: jest.fn().mockResolvedValue(undefined),
}));
jest.mock('../../src/services/notification.service', () => ({
  onBookingWaitingApproval: jest.fn().mockResolvedValue(undefined),
}));
jest.mock('../../src/services/blockchain.service', () => ({ blockchainService: {} }));
jest.mock('../../src/services/chain-registry.service', () => ({
  enqueueBookingCreate: jest.fn().mockResolvedValue(undefined),
  enqueueSafely: jest.fn(),
}));
jest.mock('../../src/shared/analytics', () => ({ track: jest.fn() }));

function fakeTx(recent: unknown) {
  return {
    adminNotification: {
      findFirst: jest.fn().mockResolvedValue(recent),
      create: jest.fn().mockResolvedValue({}),
    },
  };
}

describe('recordQrRequestedForAdmins', () => {
  it('crea el aviso la primera vez', async () => {
    const tx = fakeTx(null);
    const created = await recordQrRequestedForAdmins(tx as never, 'booking-1', 'caregiver-1');
    expect(created).toBe(true);
    expect(tx.adminNotification.create).toHaveBeenCalledWith({
      data: { type: 'PAYMENT_APPROVAL_REQUEST', caregiverId: 'caregiver-1', bookingId: 'booking-1' },
    });
  });

  it('no duplica si ya hay un aviso reciente de esa reserva', async () => {
    const tx = fakeTx({ id: 'n-1' });
    const created = await recordQrRequestedForAdmins(tx as never, 'booking-1', 'caregiver-1');
    expect(created).toBe(false);
    expect(tx.adminNotification.create).not.toHaveBeenCalled();
  });

  it('solo mira avisos de los últimos 30 minutos de ESA reserva', async () => {
    const tx = fakeTx(null);
    await recordQrRequestedForAdmins(tx as never, 'booking-9', 'caregiver-1');
    const where = tx.adminNotification.findFirst.mock.calls[0][0].where;
    expect(where.bookingId).toBe('booking-9');
    expect(where.type).toBe('PAYMENT_APPROVAL_REQUEST');
    const ageMs = Date.now() - (where.createdAt.gte as Date).getTime();
    expect(ageMs).toBeGreaterThan(29 * 60 * 1000);
    expect(ageMs).toBeLessThan(31 * 60 * 1000);
  });
});
