/**
 * Agrega los eventos crudos de analítica a AnalyticsDaily y poda lo viejo.
 * Cada hora recalcula hoy y ayer (idempotente); a las 03:40 además poda
 * eventos (>90d) y sesiones (>400d) para que la base no crezca sin límite.
 */
import cron from 'node-cron';
import logger from '../shared/logger.js';
import { rollupDay, purgeOld } from '../modules/analytics/analytics.service.js';

const dayStr = (offsetDays: number) => {
  const d = new Date(Date.now() - offsetDays * 86_400_000);
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'America/La_Paz' }).format(d); // YYYY-MM-DD
};

export async function ejecutarRollupAnalytics(): Promise<void> {
  try {
    await rollupDay(dayStr(1));
    await rollupDay(dayStr(0));
  } catch (err) {
    logger.warn('[ANALYTICS ROLLUP] falló', { err: (err as Error).message });
  }
}

export function iniciarJobAnalyticsRollup() {
  cron.schedule('5 * * * *', () => { void ejecutarRollupAnalytics(); });
  cron.schedule('40 3 * * *', async () => {
    try {
      const r = await purgeOld();
      logger.info('[ANALYTICS ROLLUP] poda', r);
    } catch (err) {
      logger.warn('[ANALYTICS ROLLUP] poda falló', { err: (err as Error).message });
    }
  });
  logger.info('[ANALYTICS ROLLUP JOB] activo (hora a hora + poda diaria).');
}
