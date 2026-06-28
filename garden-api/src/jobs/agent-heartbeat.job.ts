/**
 * Agent Heartbeat Job
 * Escribe un log de salud cada 15 minutos para que el Monitor de Agentes
 * siempre muestre actividad, incluso cuando no hay eventos importantes.
 * También revisa el balance del wallet blockchain cada hora y envía
 * un email de alerta al admin cuando baja de 0.05 POL.
 */
import cron from 'node-cron';
import { ethers } from 'ethers';
import { logAgentCall } from '../shared/agent-logger.js';
import { sendTransactionalEmail } from '../modules/auth/email.service.js';
import prisma from '../config/database.js';
import { env } from '../config/env.js';
import logger from '../shared/logger.js';

// ── Alerta de balance blockchain ────────────────────────────────────────────

const BALANCE_ALERT_THRESHOLD = 0.05; // POL — envía alerta por debajo de este valor
let _lastAlertSentAt: number | null = null;
const ALERT_COOLDOWN_MS = 6 * 60 * 60 * 1000; // no spamear: máximo 1 alerta cada 6 horas

async function checkBlockchainBalance(): Promise<void> {
  if (!env.BLOCKCHAIN_ENABLED || !env.BLOCKCHAIN_RPC_URL || !env.BLOCKCHAIN_PRIVATE_KEY) return;

  try {
    const provider = new ethers.JsonRpcProvider(env.BLOCKCHAIN_RPC_URL);
    const wallet = new ethers.Wallet(env.BLOCKCHAIN_PRIVATE_KEY, provider);
    const balance = await provider.getBalance(wallet.address);
    const balancePol = parseFloat(ethers.formatEther(balance));
    const feeData = await provider.getFeeData();
    const gasPrice = feeData.gasPrice ?? BigInt(30_000_000_000);
    const txsLeft = balance > 0n
      ? Number(balance / (gasPrice * BigInt(120_000)))
      : 0;

    logger.info('[HEARTBEAT] Blockchain wallet balance', {
      address: wallet.address,
      balancePol: balancePol.toFixed(6),
      txsLeft,
    });

    if (balancePol < BALANCE_ALERT_THRESHOLD) {
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
            <p>El wallet de GARDEN en Polygon Amoy tiene poco saldo y las próximas
            escrituras en blockchain podrían fallar.</p>
            <table style="width:100%;border-collapse:collapse;margin:16px 0">
              <tr style="background:#f7f7f7">
                <td style="padding:10px;font-weight:bold">Dirección</td>
                <td style="padding:10px;font-family:monospace">${wallet.address}</td>
              </tr>
              <tr>
                <td style="padding:10px;font-weight:bold">Balance actual</td>
                <td style="padding:10px;color:#e53e3e;font-weight:bold">${balancePol.toFixed(6)} POL</td>
              </tr>
              <tr style="background:#f7f7f7">
                <td style="padding:10px;font-weight:bold">Txs restantes aprox.</td>
                <td style="padding:10px">~${txsLeft}</td>
              </tr>
            </table>
            <p><strong>Acción requerida:</strong> Recarga el wallet con al menos <strong>0.5 POL</strong>
            desde el faucet o transferencia.</p>
            <p style="color:#888;font-size:12px">Este email se envía máximo una vez cada 6 horas.</p>
          </div>
        `,
      ).catch(err => logger.error('[HEARTBEAT] Error enviando alerta de balance', { err }));

      logger.warn('[HEARTBEAT] ⚠️ Balance bajo — alerta enviada al admin', {
        balancePol,
        txsLeft,
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
