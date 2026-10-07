/**
 * POST /api/bookings/:id/cancel — cuándo se exige el motivo.
 * La app cancela sola al vencer el QR (o si el cliente sale del pago) con source QR_ABANDONED y
 * sin motivo: antes eso siempre daba 400 y la reserva quedaba ocupando el horario.
 */
import { cancelBookingBodySchema } from '../../src/modules/booking-service/booking.validation';

const ok = (body: unknown) => cancelBookingBodySchema.safeParse(body).success;

describe('cancelBookingBodySchema', () => {
  it('cancelación automática por QR vencido o pago abandonado: sin motivo es válida', () => {
    expect(ok({ reason: 'QR de pago expirado o cancelado por el usuario', source: 'QR_ABANDONED' })).toBe(true);
    expect(ok({ source: 'PAYMENT_TIMEOUT' })).toBe(true);
  });

  it('cancelación del cliente: el motivo sigue siendo obligatorio', () => {
    const r = cancelBookingBodySchema.safeParse({ source: 'CLIENT_REQUEST' });
    expect(r.success).toBe(false);
    if (!r.success) expect(r.error.issues[0]!.message).toBe('Debes indicar el motivo de la cancelación');
    expect(ok({})).toBe(false);
    expect(ok({ reasonCode: 'CAMBIO_DE_PLANES' })).toBe(true);
  });

  it('"Otro" exige describir el motivo, también en cancelaciones automáticas', () => {
    expect(ok({ reasonCode: 'OTRO' })).toBe(false);
    expect(ok({ reasonCode: 'OTRO', reason: 'me mudo' })).toBe(true);
    expect(ok({ reasonCode: 'OTRO', source: 'QR_ABANDONED' })).toBe(false);
  });

  it('un motivo inválido se rechaza', () => {
    expect(ok({ reasonCode: 'CUALQUIERA' })).toBe(false);
    expect(ok({ source: 'OTRO_ORIGEN' })).toBe(false);
  });
});
