/**
 * Paseos fijos: cada paseo se genera 2 días antes de su fecha. Antes se generaba el mismo día a
 * las 02:00, sin las 24 h de anticipación mínima, y createBooking lo rechazaba siempre.
 */
import prisma from '../../src/config/database';
import { generateDueOccurrences } from '../../src/modules/recurring-booking/recurring-booking.service';
import * as bookingService from '../../src/modules/booking-service/booking.service';

jest.mock('../../src/config/database', () => ({
  __esModule: true,
  default: {
    recurringBookingSeries: { findMany: jest.fn(), update: jest.fn() },
    booking: { findFirst: jest.fn().mockResolvedValue(null), update: jest.fn() },
    notification: { create: jest.fn() },
  },
}));
jest.mock('../../src/services/firebase.service', () => ({ sendPushToUser: jest.fn().mockResolvedValue(undefined) }));
jest.mock('../../src/modules/booking-service/booking.service', () => ({
  createBooking: jest.fn().mockResolvedValue({ id: 'b1' }),
  initPayment: jest.fn().mockResolvedValue({}),
  assertPetsFitCaregiver: jest.fn(),
}));

const db = prisma as any;
const DAY = 86_400_000;
// Fecha de hoy en Bolivia (UTC-4), igual que el servicio.
const today = new Date(Date.now() - 4 * 3_600_000).toISOString().slice(0, 10);
const plus = (d: number) => new Date(new Date(today + 'T00:00:00Z').getTime() + d * DAY);
const series = (id: string, date: Date) => ({
  id, clientId: 'c1', caregiverId: 'cp1', daysOfWeek: [1, 2, 3, 4, 5, 6, 7], timeSlot: 'MANANA', startTime: null,
  duration: 60, petIds: ['p1'], nextRunDate: date, generateDaysAheadDays: 2, status: 'ACTIVE',
});

beforeEach(() => jest.clearAllMocks());

it('genera el paseo de pasado mañana, no el de dentro de 3 días', async () => {
  db.recurringBookingSeries.findMany.mockResolvedValue([series('s2', plus(2)), series('s3', plus(3))]);
  const r = await generateDueOccurrences();
  expect(bookingService.createBooking).toHaveBeenCalledTimes(1);
  expect((bookingService.createBooking as jest.Mock).mock.calls[0][1].walkDate).toBe(plus(2).toISOString().slice(0, 10));
  expect(r.generated).toBe(1);
});

it('una fecha que ya pasó se reprograma sin intentar reservarla', async () => {
  db.recurringBookingSeries.findMany.mockResolvedValue([series('old', plus(-3))]);
  await generateDueOccurrences();
  expect(bookingService.createBooking).not.toHaveBeenCalled();
  expect(db.recurringBookingSeries.update).toHaveBeenCalledTimes(1);
  expect(db.notification.create).not.toHaveBeenCalled();
});
