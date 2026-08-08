/**
 * Job de lista de espera de cuidadores (≈ waitlist de Airbnb para
 * alojamientos top). Corre una vez al día (07:00 UTC = 03:00 Bolivia).
 * Reusa getAvailabilityCalendar() — el mismo chequeo real de disponibilidad
 * que ya se usa en el perfil del cuidador — para avisar a los clientes en
 * lista de espera apenas el cuidador tenga al menos un bloque libre en los
 * próximos 7 días, con cooldown de 3 días para no spamear.
 */

import cron from 'node-cron';
import logger from '../shared/logger.js';
import { checkWaitlistsAndNotify } from '../modules/caregiver-service/waitlist.service.js';

export function iniciarJobCaregiverWaitlist() {
  cron.schedule('0 7 * * *', async () => {
    await checkWaitlistsAndNotify();
  });
  logger.info('[WAITLIST JOB] Lista de espera de cuidadores activa.');
}
