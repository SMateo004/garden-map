/**
 * Helpers para convertir fecha+hora "de pared" en Bolivia (UTC-4 todo el año,
 * sin horario de verano) al instante UTC real correspondiente.
 *
 * Por qué existe: los servidores (Render, y probablemente cualquier
 * contenedor sin TZ explícita) corren en UTC por default. Cualquier cálculo
 * que use `Date.setHours()`/`new Date(y, m, d, h, min)` interpreta esas horas
 * en la zona horaria del PROCESO, no en la de Bolivia — un desfase de 4 horas
 * que ya causó un bug real: el job de no-show cancelaba reservas CONFIRMED
 * apenas llegaba su hora de inicio (según el reloj de Bolivia), ignorando por
 * completo el período de gracia configurado, porque el cálculo del servidor
 * ya las consideraba "vencidas" desde 4 horas antes.
 */

/** dateStr: "YYYY-MM-DD", timeStr opcional "HH:mm" (default 00:00). */
export function boliviaDateTimeToMs(dateStr: string, timeStr?: string): number {
  const [year, month, day] = dateStr.split('-').map(Number);
  const [hour, minute] = (timeStr || '00:00').split(':').map(Number);
  return Date.UTC(year as number, (month as number) - 1, day as number, (hour as number) + 4, (minute as number) || 0);
}

/** Igual que boliviaDateTimeToMs pero recibe un Date (ej. columna DATE de Prisma) en vez de un string. */
export function boliviaDateAndTimeToMs(date: Date, timeStr?: string): number {
  const dateStr = date.toISOString().split('T')[0]!;
  return boliviaDateTimeToMs(dateStr, timeStr);
}
