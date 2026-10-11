import {
  ARRIVAL_OPENS_MINUTES_BEFORE,
  EN_ROUTE_OPENS_MINUTES_BEFORE,
  describeOpening,
  preStartOpensAtMs,
  scheduledStartMs,
} from '../../src/utils/service-window';

// Bolivia es UTC-4 todo el año: 09:30 en La Paz/Santa Cruz = 13:30 UTC.
const paseo = (time: string | null, slot: string | null = null) => ({
  serviceType: 'PASEO',
  walkDate: new Date('2026-10-12T00:00:00.000Z'),
  startTime: time,
  timeSlot: slot,
});

describe('service-window', () => {
  it('paseo con hora exacta: "en camino" abre 60 min antes y "llegué" 30 min antes', () => {
    const start = Date.UTC(2026, 9, 12, 13, 30); // 09:30 Bolivia
    expect(scheduledStartMs(paseo('09:30'))).toBe(start);
    expect(preStartOpensAtMs(paseo('09:30'), EN_ROUTE_OPENS_MINUTES_BEFORE)).toBe(start - 60 * 60 * 1000);
    expect(preStartOpensAtMs(paseo('09:30'), ARRIVAL_OPENS_MINUTES_BEFORE)).toBe(start - 30 * 60 * 1000);
  });

  it('sin hora exacta usa la hora del turno', () => {
    expect(scheduledStartMs(paseo(null, 'TARDE'))).toBe(Date.UTC(2026, 9, 12, 18, 0)); // 14:00 Bolivia
    expect(scheduledStartMs(paseo(null, 'MANANA'))).toBe(Date.UTC(2026, 9, 12, 12, 0)); // 08:00
    expect(scheduledStartMs(paseo(null, 'NOCHE'))).toBe(Date.UTC(2026, 9, 12, 23, 0)); // 19:00
  });

  it('guardería usa su hora de inicio igual que el paseo', () => {
    const g = { ...paseo('15:00'), serviceType: 'GUARDERIA' };
    expect(preStartOpensAtMs(g, ARRIVAL_OPENS_MINUTES_BEFORE)).toBe(Date.UTC(2026, 9, 12, 18, 30)); // 14:30 Bolivia
  });

  it('hospedaje no tiene hora: ambos avisos abren al empezar el día (medianoche de Bolivia)', () => {
    const h = { serviceType: 'HOSPEDAJE', startDate: new Date('2026-10-12T00:00:00.000Z') };
    const midnightBolivia = Date.UTC(2026, 9, 12, 4, 0);
    expect(preStartOpensAtMs(h, EN_ROUTE_OPENS_MINUTES_BEFORE)).toBe(midnightBolivia);
    expect(preStartOpensAtMs(h, ARRIVAL_OPENS_MINUTES_BEFORE)).toBe(midnightBolivia);
  });

  it('sin fecha no restringe', () => {
    expect(preStartOpensAtMs({ serviceType: 'PASEO' }, 30)).toBeNull();
    expect(preStartOpensAtMs({ serviceType: 'HOSPEDAJE' }, 30)).toBeNull();
  });

  it('describeOpening dice "hoy" o la fecha, en hora de Bolivia', () => {
    const opens = Date.UTC(2026, 9, 12, 12, 30); // 08:30 Bolivia del 12/10
    const sameDay = Date.UTC(2026, 9, 12, 11, 0); // 07:00 Bolivia
    const dayBefore = Date.UTC(2026, 9, 11, 15, 0); // 11:00 Bolivia del 11/10
    expect(describeOpening(opens, sameDay)).toBe('hoy desde las 08:30');
    expect(describeOpening(opens, dayBefore)).toBe('el 12/10 desde las 08:30');
    expect(describeOpening(opens, dayBefore, true)).toBe('el 12/10');
  });
});
