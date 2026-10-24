/**
 * Resumen de pago del historial con recojo/entrega: lo devuelto por un viaje cancelado
 * suelto (su propia devolución) y lo devuelto DENTRO del reembolso al cancelar toda la
 * reserva se muestran por separado, para que no parezca una devolución doble.
 */
import { describe, it, expect, beforeEach } from '@jest/globals';

const booking: any = {};
jest.mock('../../src/config/database', () => ({
  __esModule: true,
  default: {
    booking: { findUnique: jest.fn(async () => booking) },
    walletTransaction: { findMany: jest.fn(async () => []) },
    adminAction: { findMany: jest.fn(async () => []) },
  },
}));
jest.mock('../../src/services/chain-registry.service.js', () => ({ getBookingChainProof: jest.fn(async () => ({ records: [] })) }));

import { getBookingHistory } from '../../src/modules/booking-service/booking-history.service.js';

const leg = (over: Record<string, unknown>) => ({
  kind: 'PICKUP', status: 'CANCELLED', fee: 15, tax: 0, refundedAmount: 15, cancelReason: null,
  enRouteAt: null, arrivedAt: null, doneAt: null, atBaseAt: null, cancelledAt: new Date(), cancelledBy: 'CLIENT', ...over,
});

beforeEach(() => {
  Object.keys(booking).forEach((k) => delete booking[k]);
  Object.assign(booking, {
    id: 'b1', clientId: 'client', caregiver: { userId: 'cg' }, status: 'CANCELLED', serviceType: 'HOSPEDAJE',
    totalAmount: 158, commissionAmount: 23, taxAmount: 0, walletPaymentAmount: 0, donationAmount: 0, tipAmount: 0,
    paidAt: new Date(), createdAt: new Date(), cancelledAt: new Date(), refundAmount: 148, refundStatus: 'APPROVED',
    transportAmount: 0, transportTaxAmount: 0, transportRefundAmount: 15, serviceEvents: [], dispute: null, review: null,
    transportLegs: [],
  });
});

describe('historial: devoluciones del recojo/entrega', () => {
  it('cancelar toda la reserva: el viaje va "incluido en el reembolso", no como devolución aparte', async () => {
    booking.transportLegs = [leg({ cancelReason: 'Reserva cancelada' })];
    const h = await getBookingHistory('b1', 'client');
    expect(h.payment.transportRefundedInRefund).toBe(15);
    expect(h.payment.transportRefunded).toBe(0);
  });

  it('viaje cancelado suelto: devolución aparte', async () => {
    booking.status = 'CONFIRMED';
    booking.refundAmount = null;
    booking.transportLegs = [leg({ cancelReason: 'Lo llevo yo' })];
    const h = await getBookingHistory('b1', 'client');
    expect(h.payment.transportRefunded).toBe(15);
    expect(h.payment.transportRefundedInRefund).toBe(0);
  });

  it('las dos cosas: el recojo se canceló antes y la entrega con la reserva', async () => {
    booking.transportRefundAmount = 25;
    booking.transportLegs = [
      leg({ cancelReason: 'Lo llevo yo' }),
      leg({ kind: 'DROPOFF', fee: 10, refundedAmount: 10, cancelReason: 'Reserva cancelada' }),
    ];
    const h = await getBookingHistory('b1', 'client');
    expect(h.payment.transportRefunded).toBe(15);
    expect(h.payment.transportRefundedInRefund).toBe(10);
  });
});
