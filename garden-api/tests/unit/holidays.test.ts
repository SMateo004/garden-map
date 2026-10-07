/**
 * Feriados nacionales de Bolivia (BOLIVIA_HOLIDAYS). Las fechas móviles se calculan a partir de la
 * Pascua: una lista copiada a mano ya tuvo errores (Carnaval 2025 y Corpus Christi 2026).
 */
import { BOLIVIA_HOLIDAYS, dayTypeOf } from '../../src/shared/availability-utils';

/** Domingo de Pascua (algoritmo anónimo gregoriano / Meeus-Jones-Butcher). */
function easter(year: number): Date {
  const a = year % 19;
  const b = Math.floor(year / 100);
  const c = year % 100;
  const d = Math.floor(b / 4);
  const e = b % 4;
  const f = Math.floor((b + 8) / 25);
  const g = Math.floor((b - f + 1) / 3);
  const h = (19 * a + b - d - g + 15) % 30;
  const i = Math.floor(c / 4);
  const k = c % 4;
  const l = (32 + 2 * e + 2 * i - h - k) % 7;
  const m = Math.floor((a + 11 * h + 22 * l) / 451);
  const month = Math.floor((h + l - 7 * m + 114) / 31);
  const day = ((h + l - 7 * m + 114) % 31) + 1;
  return new Date(Date.UTC(year, month - 1, day));
}
const plus = (d: Date, days: number) => new Date(d.getTime() + days * 86400000).toISOString().slice(0, 10);

const years = [...new Set([...BOLIVIA_HOLIDAYS].map((s) => Number(s.slice(0, 4))))];

describe('BOLIVIA_HOLIDAYS', () => {
  it('Pascua: el algoritmo coincide con fechas conocidas', () => {
    expect(easter(2025).toISOString().slice(0, 10)).toBe('2025-04-20');
    expect(easter(2026).toISOString().slice(0, 10)).toBe('2026-04-05');
    expect(easter(2027).toISOString().slice(0, 10)).toBe('2027-03-28');
  });

  it.each(years)('%i: feriados fijos', (y) => {
    for (const md of ['01-01', '01-22', '05-01', '06-21', '08-06', '11-02', '12-25']) {
      const d = `${y}-${md}`;
      // Si cae domingo se traslada al lunes: se acepta cualquiera de los dos.
      const sunday = new Date(`${d}T00:00:00Z`).getUTCDay() === 0;
      expect(BOLIVIA_HOLIDAYS.has(d) || (sunday && BOLIVIA_HOLIDAYS.has(plus(new Date(`${d}T00:00:00Z`), 1)))).toBe(true);
    }
  });

  it.each(years)('%i: fechas móviles calculadas desde la Pascua', (y) => {
    const e = easter(y);
    const expected = {
      'Carnaval lunes': plus(e, -48),
      'Carnaval martes': plus(e, -47),
      'Viernes Santo': plus(e, -2),
      'Sábado Santo': plus(e, -1),
      'Corpus Christi': plus(e, 60),
    };
    for (const [name, date] of Object.entries(expected)) {
      expect({ name, date, presente: BOLIVIA_HOLIDAYS.has(date) }).toEqual({ name, date, presente: true });
    }
  });

  it('cada año tiene exactamente 13 feriados (sin fechas sueltas viejas)', () => {
    for (const y of years) expect([...BOLIVIA_HOLIDAYS].filter((s) => s.startsWith(`${y}-`))).toHaveLength(13);
  });

  it('2027 está cargado: Carnaval 8-9 feb, Viernes Santo 26 mar, Corpus 27 may', () => {
    for (const d of ['2027-01-01', '2027-01-22', '2027-02-08', '2027-02-09', '2027-03-26', '2027-05-27', '2027-12-25']) {
      expect(dayTypeOf(new Date(d))).toBe('HOLIDAY');
    }
  });

  it('desde noviembre, la lista ya cubre el año siguiente (se reserva hasta 30 días antes)', () => {
    const now = new Date();
    const nextYear = now.getUTCFullYear() + 1;
    if (now.getUTCMonth() >= 10) {
      expect(years).toContain(nextYear);
    } else {
      expect(years).toContain(now.getUTCFullYear());
    }
  });
});
