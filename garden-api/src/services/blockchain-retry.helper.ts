import prisma from '../config/database.js';
import logger from '../shared/logger.js';
import { sendPushToAdmins } from './firebase.service.js';

interface DispatchOnChainOptions {
  bookingId: string;
  label: string;
  action: () => Promise<string | null>;
  onSuccess?: (txHash: string) => Promise<void>;
  maxAttempts?: number;
}

/**
 * Ejecuta una escritura on-chain con reintentos (backoff exponencial: 1s, 2s).
 * Si se agotan los intentos, crea un AdminNotification tipo BLOCKCHAIN_FAILURE
 * — visible en GET /api/admin/blockchain/status — en vez de perderse en un log.
 *
 * `action` debe ser uno de los métodos de blockchain.service.ts: solo relanzan
 * errores reales de tx, no los no-ops legítimos (modo mock, duplicado ya
 * existente) — esos devuelven null sin lanzar, y acá se tratan como éxito
 * silencioso (nada que reintentar ni de qué avisar).
 *
 * Siempre fire-and-forget: nunca lanza hacia el llamador.
 */
export async function dispatchOnChainWithRetry({
  bookingId,
  label,
  action,
  onSuccess,
  maxAttempts = 3,
}: DispatchOnChainOptions): Promise<void> {
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      const txHash = await action();
      if (txHash && onSuccess) {
        await onSuccess(txHash);
      }
      if (attempt > 1) {
        logger.info(`[Blockchain] ${label} succeeded after retry`, { bookingId, attempt });
      }
      return;
    } catch (err: any) {
      logger.warn(`[Blockchain] ${label} attempt ${attempt}/${maxAttempts} failed`, {
        bookingId,
        error: err?.reason || err?.message || err,
      });
      if (attempt < maxAttempts) {
        await new Promise((r) => setTimeout(r, 1000 * 2 ** (attempt - 1)));
      }
    }
  }

  logger.error(`[Blockchain] ${label} failed after all retries — admin notification created`, { bookingId });
  await prisma.adminNotification
    .create({ data: { type: 'BLOCKCHAIN_FAILURE', bookingId, caregiverId: '' } })
    .catch(() => {});

  // Push a admins — sin esto, la falla queda enterrada hasta que alguien
  // entra a la pantalla de Blockchain por su cuenta a revisar.
  sendPushToAdmins(
    '⛓️ Falla de sincronización blockchain',
    `Reserva ${bookingId.slice(0, 8).toUpperCase()} — se agotaron los 3 reintentos de "${label}". Revisar en Panel Admin → Blockchain.`,
    { type: 'BLOCKCHAIN_FAILURE', bookingId }
  ).catch(() => {});
}
