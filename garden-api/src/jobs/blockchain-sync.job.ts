/**
 * Blockchain Sync Job
 * - Cada minuto: procesa la cola persistente de registros on-chain (BlockchainRecord).
 * - Cada 10 minutos: reconcilia — encola reservas pagadas/terminadas sin su registro.
 * Ver services/chain-registry.service.ts.
 */
import cron from 'node-cron';
import logger from '../shared/logger.js';
import { processQueue, reconcile } from '../services/chain-registry.service.js';

let lastPausedReason: string | null = null;

async function tick(): Promise<void> {
  const summary = await processQueue();
  if (summary.paused) {
    // Se loguea solo al cambiar de motivo, no cada minuto.
    if (summary.paused !== lastPausedReason) {
      logger.warn('[Blockchain] Cola en pausa: no se envía nada a la cadena', { reason: summary.paused });
      lastPausedReason = summary.paused;
    }
    return;
  }
  if (lastPausedReason) {
    logger.info('[Blockchain] Cola reanudada', { previousReason: lastPausedReason });
    lastPausedReason = null;
  }
  if (summary.confirmed || summary.failed || summary.retried) {
    logger.info('[Blockchain] Ciclo de la cola', summary);
  }
}

export function iniciarJobBlockchainSync(): void {
  cron.schedule('* * * * *', () => {
    tick().catch((err) => logger.error('[Blockchain] Error en el ciclo de la cola', { error: err?.message ?? err }));
  });
  cron.schedule('*/10 * * * *', () => {
    reconcile().catch((err) => logger.error('[Blockchain] Error en la reconciliación', { error: err?.message ?? err }));
  });
  // Al arrancar: reconciliar una vez (cubre lo que pasó con el servidor caído).
  setTimeout(() => {
    reconcile().catch((err) => logger.error('[Blockchain] Error en la reconciliación inicial', { error: err?.message ?? err }));
  }, 30_000).unref?.();
}
