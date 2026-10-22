/**
 * Libera las propinas "por cobrar" cuyo dueño ya saldó su deuda (ver
 * tip-release.service.ts). El pago por QR/SIP las libera en el momento; este
 * barrido cubre cualquier otra forma de saldar (reembolso, ajuste de admin).
 */
import { scheduleExclusive } from './job-lease.js';
import logger from '../shared/logger.js';
import { releaseAllPendingTips } from '../modules/booking-service/tip-release.service.js';

export function iniciarJobLiberarPropinas() {
  scheduleExclusive('tip-release', '*/30 * * * *', async () => {
    try {
      await releaseAllPendingTips();
    } catch (err) {
      logger.error('[TIP-RELEASE JOB] Falló el barrido de propinas por cobrar', { err });
    }
  });
  logger.info('[TIP-RELEASE JOB] Barrido de propinas por cobrar cada 30 min activo.');
}
