/**
 * Mensaje cuando el cuidador no trabaja ese tipo de día. El feriado gana sobre el día de la
 * semana: antes un feriado en lunes decía "no trabaja los días laborables".
 */
import { dayTypeOf, dayTypeUnavailableMessage } from '../../src/shared/availability-utils';

const d = (iso: string) => new Date(iso);

describe('dayTypeOf', () => {
  it('feriado gana sobre el día de la semana', () => {
    expect(dayTypeOf(d('2026-10-12'))).toBe('HOLIDAY'); // lunes, Día de la Descolonización
    expect(dayTypeOf(d('2026-11-02'))).toBe('HOLIDAY'); // lunes, Día de los Difuntos
  });
  it('fin de semana y día hábil', () => {
    expect(dayTypeOf(d('2026-10-10'))).toBe('WEEKEND'); // sábado
    expect(dayTypeOf(d('2026-10-11'))).toBe('WEEKEND'); // domingo
    expect(dayTypeOf(d('2026-10-13'))).toBe('WEEKDAY'); // martes
  });
});

describe('dayTypeUnavailableMessage', () => {
  it('feriado: lo dice con la fecha legible', () => {
    expect(dayTypeUnavailableMessage(d('2026-10-12'))).toBe(
      'El cuidador no trabaja en feriados y el lunes 12 de octubre es feriado. Elige otra fecha.'
    );
  });
  it('fin de semana', () => {
    expect(dayTypeUnavailableMessage(d('2026-10-10'))).toBe(
      'El cuidador no trabaja los fines de semana (sábado 10 de octubre). Elige otra fecha.'
    );
  });
  it('día hábil', () => {
    expect(dayTypeUnavailableMessage(d('2026-10-13'))).toBe(
      'El cuidador no trabaja de lunes a viernes (martes 13 de octubre). Elige otra fecha.'
    );
  });
});
