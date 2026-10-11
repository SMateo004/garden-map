import { boliviaDateAndTimeToMs } from './bolivia-time.js';

/**
 * Ventanas de tiempo previas al inicio de un servicio.
 *
 * El cuidador no puede avisar "voy en camino" ni "ya llegué" mucho antes de la hora del
 * servicio: no tendría sentido llegar antes de tiempo, y esos avisos le llegan al dueño como
 * notificación. Un paseo de las 15:00 no debería mostrar "ya llegó" a las 9 de la mañana.
 *
 *  - "En camino" abre 60 min antes de la hora (tiempo razonable de traslado).
 *  - "Ya llegué" abre 30 min antes (misma apertura que la ventana para iniciar el paseo).
 *  - Hospedaje no tiene hora, solo día: ambos abren al empezar ese día (hora de Bolivia).
 *
 * No hay límite superior: avisar tarde sigue siendo válido.
 */
export const EN_ROUTE_OPENS_MINUTES_BEFORE = 60;
export const ARRIVAL_OPENS_MINUTES_BEFORE = 30;

/** Hora de referencia de cada turno cuando la reserva no trae hora exacta (igual que la app). */
const SLOT_START: Record<string, string> = { MANANA: '08:00', TARDE: '14:00', NOCHE: '19:00' };

export interface ServiceSchedule {
  serviceType: string;
  startDate?: Date | null;
  walkDate?: Date | null;
  startTime?: string | null;
  timeSlot?: string | null;
}

/** Instante (ms UTC) en que empieza el servicio según su fecha y hora de Bolivia, o null si no se sabe. */
export function scheduledStartMs(b: ServiceSchedule): number | null {
  if (b.serviceType === 'HOSPEDAJE') {
    return b.startDate ? boliviaDateAndTimeToMs(b.startDate) : null;
  }
  if (!b.walkDate) return null;
  const time = b.startTime && b.startTime.includes(':') ? b.startTime : b.timeSlot ? SLOT_START[b.timeSlot] : undefined;
  return boliviaDateAndTimeToMs(b.walkDate, time);
}

/**
 * Cuándo se habilita un aviso previo al inicio: [minutesBefore] minutos antes de la hora del
 * servicio (hospedaje: al empezar el día). null = sin restricción conocida.
 */
export function preStartOpensAtMs(b: ServiceSchedule, minutesBefore: number): number | null {
  const start = scheduledStartMs(b);
  if (start === null) return null;
  return b.serviceType === 'HOSPEDAJE' ? start : start - minutesBefore * 60 * 1000;
}

/** "hoy desde las 08:30" o "el 12/10 desde las 08:30" (hora de Bolivia). dayOnly: sin la hora. */
export function describeOpening(opensAtMs: number, nowMs: number = Date.now(), dayOnly = false): string {
  const bo = new Date(opensAtMs - 4 * 60 * 60 * 1000);
  const hh = String(bo.getUTCHours()).padStart(2, '0');
  const mm = String(bo.getUTCMinutes()).padStart(2, '0');
  const today = new Date(nowMs - 4 * 60 * 60 * 1000).toISOString().slice(0, 10);
  const day = bo.toISOString().slice(0, 10);
  if (day === today) return dayOnly ? 'hoy' : `hoy desde las ${hh}:${mm}`;
  const [, m, d] = day.split('-');
  return dayOnly ? `el ${d}/${m}` : `el ${d}/${m} desde las ${hh}:${mm}`;
}
