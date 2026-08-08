/**
 * Job de generación de paseos recurrentes.
 *
 * Corre una vez al día (06:00 UTC = 02:00 Bolivia, horario de baja
 * actividad). Para cada RecurringBookingSeries ACTIVE cuya nextRunDate ya
 * llegó, genera la reserva real reusando createBooking() (hereda TODA la
 * validación existente — disponibilidad, mascotas, perfil completo — sin
 * duplicarla), intenta auto-pagar con billetera si el saldo alcanza, y
 * avanza la serie a la siguiente fecha del patrón semanal.
 *
 * Si una fecha puntual no se puede generar (cuidador sin cupo, etc.) se
 * salta SOLO esa ocurrencia — la serie sigue viva para la siguiente fecha.
 */

import cron from 'node-cron';
import logger from '../shared/logger.js';
import * as recurringBookingService from '../modules/recurring-booking/recurring-booking.service.js';

export function iniciarJobRecurringBookingGeneration() {
  cron.schedule('0 6 * * *', async () => {
    await recurringBookingService.generateDueOccurrences();
  });
  logger.info('[RECURRING-BOOKING JOB] Generador de paseos recurrentes activo.');
}
