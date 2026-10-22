/**
 * Recojo y entrega a domicilio cada 5 minutos (ver transport.service.ts
 * runTransportMaintenance): recordatorio al cuidador 1 h antes, aviso de atraso al
 * cuidador y al dueño a los 15 min, alerta a los admins a la hora, y cierre del mapa en
 * vivo del recojo si nadie marcó "ya llegamos".
 */
import cron from 'node-cron';
import logger from '../shared/logger.js';
import { runTransportMaintenance } from '../modules/transport/transport.service.js';

export function iniciarJobTransporte() {
  cron.schedule('*/5 * * * *', async () => {
    try {
      const r = await runTransportMaintenance();
      if (r.reminded || r.late || r.alerted || r.closed) logger.info('[TRANSPORT JOB]', r);
    } catch (err) {
      logger.error('[TRANSPORT JOB] falló', { err });
    }
  });
  logger.info('[TRANSPORT JOB] Recojo y entrega a domicilio activo.');
}
