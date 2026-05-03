/**
 * Agent Heartbeat Job
 * Escribe un log de salud cada 15 minutos para que el Monitor de Agentes
 * siempre muestre actividad, incluso cuando no hay eventos importantes.
 */
import cron from 'node-cron';
import { logAgentCall } from '../shared/agent-logger.js';
import prisma from '../config/database.js';
import logger from '../shared/logger.js';

export function iniciarJobAgentHeartbeat() {
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
