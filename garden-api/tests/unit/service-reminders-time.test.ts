/**
 * Los recordatorios ("empieza en 24 h / 2 h / 30 min") se calculan desde la
 * hora real del servicio en Bolivia, no desde la medianoche de la fecha: antes
 * un paseo a las 13:00 recibía "empieza en 30 minutos" la noche anterior.
 */
import { serviceStartMs, whenLabel } from '../../src/jobs/service-reminders.job';

jest.mock('../../src/config/database', () => ({ __esModule: true, default: {} }));
jest.mock('../../src/services/notification.service', () => ({ onServiceReminder: jest.fn(), getNotificationPrefs: jest.fn() }));
jest.mock('../../src/services/firebase.service', () => ({ sendPushToUser: jest.fn() }));
jest.mock('../../src/modules/booking-service/booking.service', () => ({ autoPayoutExpiredReviews: jest.fn(), calcOvertimeMinutes: jest.fn() }));

const walk = (date: string, time: string | null) => ({ walkDate: new Date(`${date}T00:00:00.000Z`), startDate: null, startTime: time });

describe('serviceStartMs', () => {
  it('paseo del 13/10 a las 13:00 de Bolivia = 17:00 UTC', () => {
    expect(new Date(serviceStartMs(walk('2026-10-13', '13:00'))!).toISOString()).toBe('2026-10-13T17:00:00.000Z');
  });

  it('el aviso de 30 min sale 12:30 de ese día, no la noche anterior', () => {
    const start = serviceStartMs(walk('2026-10-13', '13:00'))!;
    expect(new Date(start - 30 * 60 * 1000).toISOString()).toBe('2026-10-13T16:30:00.000Z'); // 12:30 Bolivia
  });

  it('sin hora (hospedaje) usa las 09:00 de Bolivia', () => {
    const b = { walkDate: null, startDate: new Date('2026-10-20T00:00:00.000Z'), startTime: null };
    expect(new Date(serviceStartMs(b)!).toISOString()).toBe('2026-10-20T13:00:00.000Z');
  });

  it('sin fecha no hay recordatorio', () => {
    expect(serviceStartMs({ walkDate: null, startDate: null, startTime: '10:00' })).toBeNull();
  });
});

describe('whenLabel', () => {
  const start = Date.parse('2026-10-13T17:00:00.000Z'); // 13/10 13:00 Bolivia
  it('un día antes dice "mañana" con fecha y hora', () => {
    expect(whenLabel(start, Date.parse('2026-10-12T17:00:00.000Z'), true)).toBe('mañana 13/10 a las 13:00');
  });
  it('el mismo día dice "hoy"', () => {
    expect(whenLabel(start, Date.parse('2026-10-13T15:00:00.000Z'), true)).toBe('hoy 13/10 a las 13:00');
  });
  it('a las 21:00 de Bolivia del día anterior sigue siendo "mañana"', () => {
    expect(whenLabel(start, Date.parse('2026-10-13T01:00:00.000Z'), true)).toBe('mañana 13/10 a las 13:00');
  });
});
