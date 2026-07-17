// ── Sentry debe inicializarse ANTES que cualquier otro módulo ─────────────────
import * as Sentry from '@sentry/node';
if (process.env.SENTRY_DSN) {
  Sentry.init({
    dsn: process.env.SENTRY_DSN,
    environment: process.env.NODE_ENV ?? 'development',
    release: process.env.npm_package_version,
    tracesSampleRate: 0.2,      // 20% de transacciones — suficiente para MVP
    attachStacktrace: true,     // stack trace even for non-Error captures (e.g. strings)
    integrations: [
      Sentry.prismaIntegration(),       // Prisma query spans
      Sentry.expressIntegration(),      // Express route/middleware spans
      Sentry.requestDataIntegration(),  // Attaches full HTTP request data to errors
    ],
    // Exclude noisy health-check pings (Render hits /health every few seconds)
    tracesSampler: (ctx) => {
      const name = ctx.name ?? '';
      if (name.includes('/health')) return 0;
      return 0.2;
    },
  });
}

// ── Process-level error handlers — before any async code ──────────────────────
// These are the last line of defence. Node exits after uncaughtException because
// the process may be in an undefined state; we log + capture to Sentry first.
process.on('uncaughtException', (err: Error) => {
  console.error('[CRITICAL] Uncaught exception:', err.message, err.stack);
  if (process.env.SENTRY_DSN) Sentry.captureException(err);
  process.exit(1);
});

process.on('unhandledRejection', (reason: unknown) => {
  const err = reason instanceof Error ? reason : new Error(String(reason));
  console.error('[CRITICAL] Unhandled promise rejection:', err.message, err.stack);
  if (process.env.SENTRY_DSN) Sentry.captureException(err);
  // Do NOT exit — the current request will bubble to the error handler naturally.
  // If it is truly unrecoverable, Sentry will alert.
});

import { createServer } from 'http';
import app from './app.js';
import { env } from './config/env.js';
import prisma from './config/database.js';
import logger from './shared/logger.js';
import { shutdownAnalytics } from './shared/analytics.js';
import { shutdownRedis } from './config/redis.js';
import { iniciarJobAjustePrecios } from './jobs/ajuste-precios.job.js';
import { iniciarJobNotificacionesProgramadas } from './jobs/scheduled-notifications.job.js';
import { iniciarJobWalkExpiry } from './jobs/walk-expiry.job.js';
import { iniciarJobAgentHeartbeat } from './jobs/agent-heartbeat.job.js';
import { iniciarJobServiceReminders } from './jobs/service-reminders.job.js';
import { iniciarJobQrExpiry } from './jobs/qr-expiry.job.js';
import { iniciarJobMgExpiry } from './jobs/mg-expiry.job.js';
import { iniciarJobSlotConflictExpiry } from './jobs/slot-conflict-expiry.job.js';
import { iniciarJobChatRetention } from './jobs/chat-retention.job.js';
import { iniciarJobCaregiverAcceptExpiry } from './jobs/caregiver-accept-expiry.job.js';
import { iniciarJobRecordatorioCapacitaciones } from './jobs/training-reminder.job.js';

const PORT = parseInt(process.env.PORT ?? '3000', 10);

const httpServer = createServer(app);

/** Maximum time (ms) to wait for in-flight requests before forcing exit. */
const SHUTDOWN_TIMEOUT_MS = 30_000;

/**
 * Graceful shutdown sequence:
 * 1. Stop accepting new HTTP connections.
 * 2. Flush analytics + close Redis + disconnect Prisma.
 * 3. Exit 0 (or 1 on error / timeout).
 *
 * Handles both SIGTERM (Render rolling deploy) and SIGINT (Ctrl-C in dev).
 */
async function shutdown(signal: string): Promise<void> {
  logger.info(`[Shutdown] ${signal} received — starting graceful shutdown`);

  // Hard-kill timer: if shutdown takes longer than SHUTDOWN_TIMEOUT_MS, force exit.
  const hardKill = setTimeout(() => {
    logger.error(`[Shutdown] Timeout after ${SHUTDOWN_TIMEOUT_MS}ms — forcing exit`);
    process.exit(1);
  }, SHUTDOWN_TIMEOUT_MS);
  hardKill.unref(); // Don't keep the event loop alive just for this timeout.

  // Stop accepting new requests; wait for in-flight ones to complete.
  httpServer.close(() => logger.info('[Shutdown] HTTP server closed'));

  try {
    await shutdownAnalytics();
    await shutdownRedis();
    await prisma.$disconnect();
    // Flush pending Sentry events before exit (2s timeout — don't block forever)
    if (process.env.SENTRY_DSN) {
      await Sentry.flush(2000).catch(() => {});
    }
    logger.info('[Shutdown] All resources released — exiting cleanly');
    clearTimeout(hardKill);
    process.exit(0);
  } catch (err) {
    logger.error('[Shutdown] Error during shutdown', err);
    process.exit(1);
  }
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT',  () => shutdown('SIGINT'));

/**
 * Verifies that the database schema is in sync with the Prisma migrations table.
 * The startCommand on Render already runs `prisma migrate resolve + migrate deploy`
 * before node starts. This check surfaces any remaining issues as a log warning
 * but does NOT exit — exiting here would kill the server after it's already
 * listening, causing all in-flight health-check requests to get connection-reset.
 */
async function assertMigrationsApplied(): Promise<void> {
  try {
    const rows = await prisma.$queryRaw<{ migration_name: string; finished_at: Date | null }[]>`
      SELECT migration_name, finished_at
      FROM "_prisma_migrations"
      WHERE finished_at IS NULL
      ORDER BY started_at DESC
      LIMIT 5
    `;
    if (rows.length > 0) {
      const names = rows.map(r => r.migration_name).join(', ');
      // Log as warning (not fatal) — the startCommand handles migration deploy.
      // Exiting here after listen() is already called causes health-check timeouts.
      logger.warn(`[Startup] ${rows.length} migration(s) have finished_at=NULL: [${names}]. ` +
        'They may be in-progress or failed. Check Render logs for migrate deploy output.');
    } else {
      logger.info('[Startup] All Prisma migrations applied ✓');
    }
  } catch (err: any) {
    // _prisma_migrations table may not exist on a fresh DB — warn, do not crash.
    logger.warn('[Startup] Could not verify migrations state', { error: (err as any)?.message });
  }
}

async function start() {
  httpServer.listen(PORT, '0.0.0.0', async () => {
    logger.info(`🚀 GARDEN API RUNNING ON http://localhost:${PORT}`);

    // Defer Socket.io to prevent main thread blocking during module load
    try {
        const { initSocketServer } = await import('./services/socket.service.js');
        initSocketServer(httpServer);
        logger.info('Socket.io initialized successfully');
    } catch (err) {
        logger.error('Failed to initialize Socket.io', err);
    }
  });

  try {
    await prisma.$connect();
    logger.info('Database connected successfully');
    await assertMigrationsApplied();
  } catch (e) {
    logger.error('Database connection failed', e);
    if (process.env.NODE_ENV !== 'production') process.exit(1);
  }

  // Seed settings defaults (solo crea si no existen — nunca sobreescribe)
  try {
    await prisma.appSettings.createMany({
      data: [
        // ── Feature flags (boolean) ──────────────────────────────────────────
        { key: 'marketplaceEnabled',       value: 'true'  },
        { key: 'paymentsEnabled',          value: 'true'  },
        { key: 'newRegistrationsEnabled',  value: 'true'  },
        { key: 'walk30Enabled',            value: 'false' },
        { key: 'maintenanceMode',          value: 'false' },
        { key: 'hospedajeEnabled',         value: 'true'  },
        { key: 'paseoEnabled',             value: 'true'  },
        { key: 'guarderiaEnabled',         value: 'true'  }, // ← faltaba seed
        { key: 'retirosEnabled',           value: 'true'  },
        { key: 'disputasEnabled',          value: 'true'  },
        { key: 'preciosDinamicosEnabled',  value: 'true'  },
        { key: 'meetGreetEnabled',         value: 'true'  },
        // ── Beta access control ──────────────────────────────────────────────
        { key: 'betaInviteRequired',       value: 'false' },
        // JSON array of valid invite codes: ["GARDEN2025","BETA01"]
        { key: 'betaInviteCodes',          value: '[]'    },
        // ── Códigos de registro especiales (string) ──────────────────────────
        { key: 'professionalRegistrationCode', value: '' }, // ← faltaba seed
        { key: 'companyRegistrationCode',      value: '' }, // ← faltaba seed
        // ── Pagos y finanzas (numeric) ───────────────────────────────────────
        { key: 'platformCommissionPct',    value: '10'    },
        { key: 'montoMinimoRetiro',        value: '50'    },
        { key: 'qrValidityMinutes',        value: '15'    },
        { key: 'autoReleasePaymentHoras',  value: '24'    },
        { key: 'onHoldSlaHoras',           value: '72'    }, // ← faltaba seed
        // Horas para que el cuidador acepte una reserva antes de cancelarse
        // automáticamente con reembolso completo a billetera. También se usa
        // como anticipación mínima requerida para poder reservar un servicio.
        { key: 'caregiverAcceptWindowHoras', value: '3'   },
        // ── Política cancelación HOSPEDAJE (numeric) ─────────────────────────
        { key: 'hospedajeRefundAdminFeeBS',    value: '10' },
        { key: 'hospedajeRefund100Horas',      value: '48' },
        { key: 'hospedajeRefund50Horas',       value: '24' },
        // ── Política cancelación PASEO (numeric) ─────────────────────────────
        { key: 'paseoRefund100Horas',      value: '12'   },
        { key: 'paseoRefund50Horas',       value: '6'    },
        // ── Límites de precio por tipo de servicio (numeric) ─────────────────
        { key: 'paseoMinPrice',            value: '20'   },
        { key: 'paseoMaxPrice',            value: '400'  },
        { key: 'hospedajeMinPrice',        value: '40'   },
        { key: 'hospedajeMaxPrice',        value: '400'  },
        { key: 'guarderiaMinPrice',        value: '15'   },
        { key: 'guarderiaMaxPrice',        value: '400'  },
        // ── Versión mínima de app (force-update) ──────────────────────────────
        { key: 'minAppVersion',            value: '1.0.0' },
        { key: 'storeUrlIos',              value: '' },
        { key: 'storeUrlAndroid',          value: '' },
        // Interruptor manual: fuerza la pantalla de actualización a TODOS los
        // usuarios al instante, sin depender de comparar minAppVersion.
        { key: 'forceUpdateEnabled',       value: 'false' },
      ],
      skipDuplicates: true, // No sobreescribe valores ya guardados por el admin
    });
    logger.info('[Settings] Defaults seeded OK');
  } catch (e) {
    logger.warn('[Settings] Could not seed defaults', e);
  }

  // Log storage status on startup
  import('./services/storage.service.js').then(m => m.logStorageStatus()).catch(() => {});

  // Defer heavy background jobs by 10s to let the API warm up
  setTimeout(() => {
    logger.info('Starting background jobs...');
    iniciarJobAjustePrecios();
    iniciarJobNotificacionesProgramadas();
    iniciarJobWalkExpiry();
    iniciarJobAgentHeartbeat();
    iniciarJobServiceReminders();
    iniciarJobQrExpiry();
    iniciarJobMgExpiry();
    iniciarJobSlotConflictExpiry();
    iniciarJobChatRetention();
    iniciarJobCaregiverAcceptExpiry();
    iniciarJobRecordatorioCapacitaciones();
  }, 10000);

  // Auto-release payment after service ends if owner hasn't reviewed
  // Hours window is configurable via 'autoReleasePaymentHoras' setting (default: 24h)
  // Runs every hour, processes any bookings past the window
  setInterval(async () => {
    try {
      const { autoReleasePayment } = await import('./modules/booking-service/booking.service.js');
      const { getNumericSetting } = await import('./utils/settings-cache.js');
      const autoReleaseHoras = await getNumericSetting('autoReleasePaymentHoras', 24);
      const cutoff = new Date(Date.now() - autoReleaseHoras * 60 * 60 * 1000);
      const overdueBookings = await prisma.booking.findMany({
        where: {
          status: 'COMPLETED',
          ownerRated: false,
          payoutStatus: 'PENDING', // excluye ON_HOLD (disputas) y PAID (ya liberados)
          serviceEndedAt: { lte: cutoff },
        },
        select: { id: true, serviceType: true },
      });
      for (const booking of overdueBookings) {
        try {
          // Use autoReleasePayment — does NOT create a fake review or inflate caregiver rating.
          // The client simply didn't rate; the system only releases the funds.
          await autoReleasePayment(booking.id, autoReleaseHoras);
          logger.info(`[AutoRelease] Booking auto-released after ${autoReleaseHoras}h`, { bookingId: booking.id, serviceType: booking.serviceType });
        } catch (err: any) {
          logger.error('[AutoRelease] Failed to auto-release booking', { bookingId: booking.id, error: err.message });
        }
      }
    } catch (err: any) {
      logger.error('[AutoRelease] Cron job failed', { error: err.message });
    }
  }, 60 * 60 * 1000); // Every hour

  // SLA: auto-release ON_HOLD bookings if admin hasn't resolved them in N days.
  // Configurable via 'onHoldSlaHoras' setting (default: 72h = 3 days).
  // Releases funds to caregiver without overriding the existing low rating.
  setInterval(async () => {
    try {
      const { getNumericSetting } = await import('./utils/settings-cache.js');
      const slaHoras = await getNumericSetting('onHoldSlaHoras', 72);
      const cutoff = new Date(Date.now() - slaHoras * 60 * 60 * 1000);
      const stuckBookings = await prisma.booking.findMany({
        where: {
          status: 'COMPLETED',
          payoutStatus: 'ON_HOLD',
          ownerRated: true,
          updatedAt: { lte: cutoff },
        },
        select: { id: true, caregiverId: true, totalAmount: true, commissionAmount: true },
      });

      for (const booking of stuckBookings) {
        try {
          await prisma.$transaction(async (tx) => {
            const claimed = await tx.booking.updateMany({
              where: { id: booking.id, payoutStatus: 'ON_HOLD' },
              data: { payoutStatus: 'PAID' },
            });
            if (claimed.count === 0) return; // already resolved by admin

            const caregiverProfile = await tx.caregiverProfile.findUnique({
              where: { id: booking.caregiverId },
              select: { userId: true },
            });
            if (!caregiverProfile) return;

            const amount = Number(booking.totalAmount) - Number(booking.commissionAmount);
            await tx.user.update({
              where: { id: caregiverProfile.userId },
              data: { balance: { increment: amount } },
            });
          });
          logger.info(`[SLA-OnHold] Booking auto-released after ${slaHoras}h SLA`, { bookingId: booking.id });
        } catch (err: any) {
          logger.error('[SLA-OnHold] Failed to release booking', { bookingId: booking.id, error: err.message });
        }
      }
    } catch (err: any) {
      logger.error('[SLA-OnHold] Cron job failed', { error: err.message });
    }
  }, 6 * 60 * 60 * 1000); // Every 6 hours
}

start().catch(err => {
  logger.error('Fatal startup error', err);
  process.exit(1);
});
