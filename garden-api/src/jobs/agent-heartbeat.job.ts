/**
 * Agent Heartbeat Job
 * Escribe un log de salud cada 15 minutos para que el Monitor de Agentes
 * siempre muestre actividad, incluso cuando no hay eventos importantes.
 * También revisa el balance del wallet blockchain cada hora y envía
 * un email de alerta al admin cuando baja del umbral de la red configurada
 * (BLOCKCHAIN_LOW_BALANCE_POL, o 3 POL en Polygon PoS / 0.05 en Amoy).
 */
import cron from 'node-cron';
import { blockchainService, networkInfo } from '../services/blockchain.service.js';
import { logAgentCall } from '../shared/agent-logger.js';
import { sendTransactionalEmail } from '../modules/auth/email.service.js';
import prisma from '../config/database.js';
import { env } from '../config/env.js';
import logger from '../shared/logger.js';

// ── Alerta de balance blockchain ────────────────────────────────────────────

let _lastAlertSentAt: number | null = null;
const ALERT_COOLDOWN_MS = 6 * 60 * 60 * 1000; // no spamear: máximo 1 alerta cada 6 horas
// Gas aproximado de una reserva completa: recordBooking + finalizeBooking (medido en hardhat-garden).
const GAS_PER_BOOKING = 220_000n;

async function checkBlockchainBalance(): Promise<void> {
  try {
    const wallet = await blockchainService.getWalletBalance();
    if (!wallet) return;
    const net = networkInfo(wallet.chainId);
    const threshold = env.BLOCKCHAIN_LOW_BALANCE_POL ?? net?.lowBalancePol ?? 0.05;
    const balanceWei = BigInt(Math.floor(wallet.balancePol * 1e18));
    const bookingsLeft = Number(balanceWei / (wallet.gasPriceWei * GAS_PER_BOOKING));

    logger.info('[HEARTBEAT] Blockchain wallet balance', {
      network: net?.name ?? wallet.chainId,
      address: wallet.address,
      balancePol: wallet.balancePol.toFixed(6),
      bookingsLeft,
    });

    if (wallet.balancePol < threshold) {
      const now = Date.now();
      if (_lastAlertSentAt && (now - _lastAlertSentAt) < ALERT_COOLDOWN_MS) return;
      _lastAlertSentAt = now;

      const adminEmail = 'marielaalejandrav61@gmail.com';
      await sendTransactionalEmail(
        adminEmail,
        '⚠️ GARDEN — Balance blockchain bajo',
        `
          <div style="font-family:sans-serif;max-width:600px;margin:0 auto;padding:24px">
            <h2 style="color:#e53e3e">⚠️ Balance del wallet blockchain bajo</h2>
            <p>El wallet de GARDEN en ${net?.name ?? `la red ${wallet.chainId}`} (${net?.label ?? ''}) tiene poco saldo.
            Mientras no se recargue, los registros quedan en cola y se envían solos cuando haya saldo.</p>
            <table style="width:100%;border-collapse:collapse;margin:16px 0">
              <tr style="background:#f7f7f7">
                <td style="padding:10px;font-weight:bold">Dirección</td>
                <td style="padding:10px;font-family:monospace">${wallet.address}</td>
              </tr>
              <tr>
                <td style="padding:10px;font-weight:bold">Balance actual</td>
                <td style="padding:10px;color:#e53e3e;font-weight:bold">${wallet.balancePol.toFixed(6)} POL</td>
              </tr>
              <tr style="background:#f7f7f7">
                <td style="padding:10px;font-weight:bold">Reservas restantes aprox.</td>
                <td style="padding:10px">~${bookingsLeft} (al precio de gas actual)</td>
              </tr>
            </table>
            <p><strong>Acción requerida:</strong> transfiere POL a esa dirección${net?.testnet ? ' (faucet de Amoy)' : ''}.
            Umbral de esta alerta: ${threshold} POL.</p>
            <p style="color:#888;font-size:12px">Este email se envía máximo una vez cada 6 horas.</p>
          </div>
        `,
      ).catch(err => logger.error('[HEARTBEAT] Error enviando alerta de balance', { err }));

      logger.warn('[HEARTBEAT] ⚠️ Balance bajo — alerta enviada al admin', {
        balancePol: wallet.balancePol,
        bookingsLeft,
      });
    }
  } catch (err) {
    logger.error('[HEARTBEAT] Error revisando balance blockchain', { err });
  }
}

export function iniciarJobAgentHeartbeat() {
  // Balance blockchain — cada hora
  cron.schedule('0 * * * *', () => { checkBlockchainBalance().catch(() => {}); });

  // Cada 15 minutos
  cron.schedule('*/15 * * * *', async () => {
    const start = Date.now();
    try {
      const [totalBookings, activeBookings, pendingPayments, approvedCaregivers] = await Promise.all([
        prisma.booking.count(),
        prisma.booking.count({ where: { status: 'IN_PROGRESS' } }),
        prisma.booking.count({ where: { status: 'PENDING_PAYMENT' } }),
        prisma.caregiverProfile.count({ where: { status: 'APPROVED' } }),
      ]);

      await logAgentCall({
        agentType: 'MONITOR',
        action: 'HEARTBEAT',
        input: { timestamp: new Date().toISOString(), interval: '15min' },
        output: {
          totalBookings,
          activeBookings,
          pendingPayments,
          approvedCaregivers,
          status: 'OK',
        },
        durationMs: Date.now() - start,
        status: 'SUCCESS',
      });
    } catch (err: any) {
      await logAgentCall({
        agentType: 'MONITOR',
        action: 'HEARTBEAT',
        input: { timestamp: new Date().toISOString() },
        output: { error: err?.message ?? 'unknown' },
        durationMs: Date.now() - start,
        status: 'ERROR',
      });
      logger.error('[HEARTBEAT] Failed', { error: err?.message });
    }
  });

  // Primer heartbeat inmediato al arrancar
  (async () => {
    await new Promise(r => setTimeout(r, 15_000)); // esperar 15s para que la DB esté lista
    const start = Date.now();
    try {
      const [totalBookings, activeBookings, approvedCaregivers] = await Promise.all([
        prisma.booking.count(),
        prisma.booking.count({ where: { status: 'IN_PROGRESS' } }),
        prisma.caregiverProfile.count({ where: { status: 'APPROVED' } }),
      ]);
      await logAgentCall({
        agentType: 'MONITOR',
        action: 'STARTUP',
        input: { timestamp: new Date().toISOString() },
        output: { totalBookings, activeBookings, approvedCaregivers, status: 'API_ONLINE' },
        durationMs: Date.now() - start,
        status: 'SUCCESS',
      });
      logger.info('[HEARTBEAT] Startup log written');
    } catch (err: any) {
      logger.error('[HEARTBEAT] Startup log failed', { error: err?.message });
    }
  })();

  logger.info('[HEARTBEAT] Agent heartbeat job started (every 15 min)');
}
