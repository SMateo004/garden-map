/**
 * El paseo dura 30 o 60 minutos: son los dos precios que fija el cuidador. Antes se aceptaba
 * hasta 240 min (reserva y serie recurrente) y todo lo que no era 30 se cobraba al precio de 60.
 */
import { paseoSchema } from '../../src/modules/booking-service/booking.validation';
import { createRecurringSeriesSchema } from '../../src/modules/recurring-booking/recurring-booking.validation';

const UUID = '00000000-0000-4000-8000-000000000001';
const paseo = (duration: unknown) => ({
  serviceType: 'PASEO', caregiverId: UUID, petIds: [UUID], walkDate: '2026-11-01', timeSlot: 'MANANA', duration,
});
const series = (duration: unknown) => ({ caregiverId: UUID, petIds: [UUID], daysOfWeek: [1, 3], timeSlot: 'MANANA', duration });

describe('duración del paseo', () => {
  it.each([30, 60, '30', '60'])('acepta %s min', (d) => {
    expect(paseoSchema.safeParse(paseo(d)).success).toBe(true);
    expect(createRecurringSeriesSchema.safeParse(series(d)).success).toBe(true);
  });

  it.each([0, 15, 45, 90, 120, 240, 61])('rechaza %s min con un mensaje claro', (d) => {
    for (const r of [paseoSchema.safeParse(paseo(d)), createRecurringSeriesSchema.safeParse(series(d))]) {
      expect(r.success).toBe(false);
      if (!r.success) expect(r.error.issues.some((i) => i.message === 'El paseo dura 30 o 60 minutos')).toBe(true);
    }
  });
});
