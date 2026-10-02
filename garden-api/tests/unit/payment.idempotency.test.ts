/**
 * Tests para idempotencia del webhook de Stripe (Fase 1).
 * Verifica que handleCheckoutCompleted ignora eventos duplicados.
 */

import { handleCheckoutCompleted } from '../../src/modules/payment-service/payment.service';
import prisma from '../../src/config/database';
import type Stripe from 'stripe';

// ── Mocks ─────────────────────────────────────────────────────────────────────

jest.mock('../../src/config/database', () => ({
  __esModule: true,
  default: {
    booking: {
      findFirst: jest.fn(),
      findUnique: jest.fn(),
      update: jest.fn(),
      updateMany: jest.fn(),
    },
  },
}));

jest.mock('../../src/services/notification.service', () => ({
  onBookingWaitingApproval: jest.fn().mockResolvedValue(undefined),
}));

jest.mock('../../src/services/blockchain.service', () => ({
  blockchainService: {
    createBookingOnChain: jest.fn().mockResolvedValue(null),
  },
}));

jest.mock('../../src/shared/analytics', () => ({
  track: jest.fn(),
}));

const mockPrisma = prisma as jest.Mocked<typeof prisma>;

// ── Fixture ───────────────────────────────────────────────────────────────────

const makeSession = (bookingId: string): Stripe.Checkout.Session =>
  ({
    id: 'cs_test_123',
    metadata: { bookingId },
    payment_intent: 'pi_test_456',
  } as unknown as Stripe.Checkout.Session);

const baseBooking = {
  id: 'booking-1',
  clientId: 'client-1',
  caregiverId: 'caregiver-1',
  totalAmount: { toNumber: () => 150 } as any,
  startDate: new Date(),
  endDate: new Date(),
  walkDate: null,
  petName: 'Rex',
  serviceType: 'HOSPEDAJE',
  paidAt: null,
  stripeEventId: null,
  blockchainTxHash: null,
};

// ── Tests ─────────────────────────────────────────────────────────────────────

describe('handleCheckoutCompleted — idempotencia Stripe', () => {
  beforeEach(() => jest.clearAllMocks());

  it('actualiza la reserva y registra stripeEventId en primer procesamiento', async () => {
    (mockPrisma.booking.findFirst as jest.Mock).mockResolvedValue(null);     // sin stripeEventId duplicado
    (mockPrisma.booking.findUnique as jest.Mock).mockResolvedValue(baseBooking); // booking encontrado

    (mockPrisma.booking.updateMany as jest.Mock).mockResolvedValue({ count: 1 });

    await handleCheckoutCompleted(makeSession('booking-1'), 'evt_first');

    expect(mockPrisma.booking.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({ id: 'booking-1', paidAt: null }),
        data: expect.objectContaining({ stripeEventId: 'evt_first' }),
      })
    );
  });

  it('ignora el evento duplicado sin llamar a updateMany (idempotencia por stripeEventId)', async () => {
    // Primera llamada a findFirst devuelve una reserva YA procesada con ese eventId
    (mockPrisma.booking.findFirst as jest.Mock).mockResolvedValueOnce({
      ...baseBooking,
      stripeEventId: 'evt_duplicate',
    });

    await handleCheckoutCompleted(makeSession('booking-1'), 'evt_duplicate');

    // No debe actualizar la reserva
    expect(mockPrisma.booking.updateMany).not.toHaveBeenCalled();
  });

  it('sale silenciosamente si la reserva no existe en la BD', async () => {
    (mockPrisma.booking.findFirst as jest.Mock).mockResolvedValue(null);  // sin stripeEventId duplicado
    (mockPrisma.booking.findUnique as jest.Mock).mockResolvedValue(null); // reserva no encontrada

    await handleCheckoutCompleted(makeSession('booking-no-existe'), 'evt_new');

    expect(mockPrisma.booking.updateMany).not.toHaveBeenCalled();
  });

  it('sale silenciosamente si la reserva ya tiene paidAt (doble proceso raro)', async () => {
    (mockPrisma.booking.findFirst as jest.Mock).mockResolvedValue(null);
    (mockPrisma.booking.findUnique as jest.Mock).mockResolvedValue({ ...baseBooking, paidAt: new Date() });

    await handleCheckoutCompleted(makeSession('booking-1'), 'evt_late');

    expect(mockPrisma.booking.updateMany).not.toHaveBeenCalled();
  });

  // FIX (auditoría 2026-10-02): caso que motivó el fix — antes el update no tenía
  // guarda atómica, así que dos entregas concurrentes del mismo webhook (ambas con
  // paidAt: null en su snapshot) procesaban ambas. Ahora, si el UPDATE condicionado
  // a paidAt IS NULL afecta 0 filas (la otra ya ganó la carrera), debe salir
  // silenciosamente sin duplicar el registro en blockchain ni la notificación.
  it('sale silenciosamente si otra solicitud concurrente ya reclamó el mismo booking (claim atómico)', async () => {
    (mockPrisma.booking.findFirst as jest.Mock).mockResolvedValue(null);
    (mockPrisma.booking.findUnique as jest.Mock).mockResolvedValue(baseBooking);
    (mockPrisma.booking.updateMany as jest.Mock).mockResolvedValue({ count: 0 });

    await handleCheckoutCompleted(makeSession('booking-1'), 'evt_race');

    expect(mockPrisma.booking.updateMany).toHaveBeenCalled();
  });
});
