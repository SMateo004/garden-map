/**
 * Mantenimiento de Premium cada 5 minutos (ver premium.service.ts runPremiumMaintenance):
 * QR sin pagar vencidos, pagos declarados que se aprueban solos al vencer el QR,
 * Premium que termina (baja en el marketplace) y aviso 3 días antes.
 */
import cron from 'node-cron';
import logger from '../shared/logger.js';
import { runPremiumMaintenance } from '../modules/premium/premium.service.js';

export function iniciarJobPremium() {
  cron.schedule('*/5 * * * *', async () => {
    try {
      const r = await runPremiumMaintenance();
      if (r.expired || r.autoApproved || r.ended || r.reminded) logger.info('[PREMIUM JOB]', r);
    } catch (err) {
      logger.error('[PREMIUM JOB] falló', { err });
    }
  });
  logger.info('[PREMIUM JOB] Mantenimiento de Premium activo.');
}
