// ── Sentry debe inicializarse ANTES que cualquier otro módulo ─────────────────
import * as Sentry from '@sentry/node';
if (process.env.SENTRY_DSN) {
  Sentry.init({
    dsn: process.env.SENTRY_DSN,
    environment: process.env.NODE_ENV ?? 'development',
    tracesSampleRate: 0.2,          // 20% de transacciones — suficiente para MVP
    profilesSampleRate: 0.1,        // 10% de profiling
    integrations: [Sentry.prismaIntegration()],
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
        { key: 'retirosEnabled',           value: 'true'  },
        { key: 'disputasEnabled',          value: 'true'  },
        { key: 'preciosDinamicosEnabled',  value: 'true'  },
        { key: 'meetGreetEnabled',         value: 'true'  },
        // ── Beta access control ──────────────────────────────────────────────
        { key: 'betaInviteRequired',       value: 'false' },
        // JSON array of valid invite codes: ["GARDEN2025","BETA01"]
        // Update via PATCH /api/admin/settings/betaInviteCodes
        { key: 'betaInviteCodes',          value: '[]'    },
        // ── Pagos y finanzas (numeric) ───────────────────────────────────────
        { key: 'platformCommissionPct',    value: '10'    },
        { key: 'montoMinimoRetiro',        value: '50'    },
        { key: 'qrValidityHours',          value: '24'    },
        { key: 'qrValidityMinutes',        value: '15'    },
        { key: 'autoReleasePaymentHoras',  value: '24'    },
        // ── Política cancelación HOSPEDAJE (numeric) ─────────────────────────
        { key: 'hospedajeRefundAdminFeeBS', value: '10'  },
        { key: 'hospedajeRefund100Horas',  value: '48'   },
        { key: 'hospedajeRefund50Horas',   value: '24'   },
        // ── Política cancelación PASEO (numeric) ─────────────────────────────
        { key: 'paseoRefund100Horas',      value: '12'   },
        { key: 'paseoRefund50Horas',       value: '6'    },
      ],
      skipDuplicates: true, // No sobreescribe valores ya guardados por el admin
    });
    logger.info('[Settings] Defaults seeded OK');
  } catch (e) {
    logger.warn('[Settings] Could not seed defaults', e);
  }

  // Defer heavy background jobs by 10s to let the API warm up
  setTimeout(() => {
    logger.info('Starting background jobs...');
    iniciarJobAjustePrecios();
    iniciarJobNotificacionesProgramadas();
    iniciarJobWalkExpiry();
  }, 10000);

  // Auto-release payment after service ends if owner hasn't reviewed
  // Hours window is configurable via 'autoReleasePaymentHoras' setting (default: 24h)
  // Runs every hour, processes any bookings past the window
  setInterval(async () => {
    try {
      const { confirmReceiptByClient } = await import('./modules/booking-service/booking.service.js');
      const { getNumericSetting } = await import('./utils/settings-cache.js');
      const autoReleaseHoras = await getNumericSetting('autoReleasePaymentHoras', 24);
      const cutoff = new Date(Date.now() - autoReleaseHoras * 60 * 60 * 1000);
      const overdueBookings = await prisma.booking.findMany({
        where: {
          status: 'COMPLETED',
          ownerRated: false,
          payoutStatus: 'PENDING',
          serviceEndedAt: { lte: cutoff },
        },
        select: { id: true, clientId: true },
      });
      for (const booking of overdueBookings) {
        try {
          await confirmReceiptByClient(booking.id, booking.clientId, 3, `Auto-liberación tras ${autoReleaseHoras}h sin reseña`);
          logger.info(`[AutoRelease] Booking auto-released after ${autoReleaseHoras}h`, { bookingId: booking.id });
        } catch (err: any) {
          logger.error('[AutoRelease] Failed to auto-release booking', { bookingId: booking.id, error: err.message });
        }
      }
    } catch (err: any) {
      logger.error('[AutoRelease] Cron job failed', { error: err.message });
    }
  }, 60 * 60 * 1000); // Every hour
}

start().catch(err => {
  logger.error('Fatal startup error', err);
  process.exit(1);
});
