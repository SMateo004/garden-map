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
import { caregiverNetOf } from './modules/pricing/pricing.service.js';
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
import { iniciarJobAnalyticsRollup } from './jobs/analytics-rollup.job.js';
import { iniciarJobNoShowExpiry } from './jobs/no-show-expiry.job.js';
import { iniciarJobHospedajeLocationPing } from './jobs/hospedaje-location-ping.job.js';
import { iniciarJobRecordatorioCapacitaciones } from './jobs/training-reminder.job.js';
import { iniciarJobSosRetry } from './jobs/sos-retry.job.js';
import { iniciarJobRecurringBookingGeneration } from './jobs/recurring-booking-generation.job.js';
import { iniciarJobInstantBookingAutoAccept } from './jobs/instant-booking-auto-accept.job.js';
import { iniciarJobCaregiverWaitlist } from './jobs/caregiver-waitlist.job.js';
import { iniciarJobBlockchainSync } from './jobs/blockchain-sync.job.js';

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
 * Verifies that the `_prisma_migrations` ledger has no dangling failed/in-progress
 * rows. NOTE: this ledger is largely disconnected from what's actually live —
 * the startCommand on Render runs `prisma db push --accept-data-loss` (see
 * render.yaml), never `migrate deploy`, so most schema changes never touch this
 * table at all. This check exists only to catch the rare case where someone runs
 * `prisma migrate dev/deploy/resolve` by hand against the live DB and leaves a
 * row unresolved (finished_at NULL). It surfaces that as a log warning but does
 * NOT exit — exiting here after listen() is already called would cause
 * in-flight health-check requests to get connection-reset.
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
      // Log as warning (not fatal) — this table doesn't gate deploys (db push does).
      // Exiting here after listen() is already called causes health-check timeouts.
      logger.warn(`[Startup] ${rows.length} migration(s) have finished_at=NULL: [${names}]. ` +
        'They may be in-progress or failed. Resolve manually with `prisma migrate resolve`.');
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
        // automáticamente con reembolso completo a billetera. También actúa
        // como piso mínimo de anticipación al reservar (ver *MinAdvanceHoras
        // abajo para el mínimo específico por tipo de servicio).
        { key: 'caregiverAcceptWindowHoras', value: '3'   },
        // Anticipación mínima (en horas) para poder reservar cada tipo de
        // servicio, configurable por separado. Default 24 = mantiene el
        // comportamiento histórico de "mínimo a partir de mañana".
        { key: 'paseoMinAdvanceHoras',      value: '24'  },
        { key: 'hospedajeMinAdvanceHoras',  value: '24'  },
        { key: 'guarderiaMinAdvanceHoras',  value: '24'  },
        // Minutos de gracia tras la hora de inicio de un servicio CONFIRMED
        // antes de marcarlo no-show y cancelarlo automáticamente sin reembolso.
        { key: 'noShowGracePeriodMinutos', value: '30'  },
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
    iniciarJobAnalyticsRollup();
    iniciarJobNoShowExpiry();
    iniciarJobRecordatorioCapacitaciones();
    iniciarJobHospedajeLocationPing();
    iniciarJobSosRetry();
    iniciarJobRecurringBookingGeneration();
    iniciarJobInstantBookingAutoAccept();
    iniciarJobCaregiverWaitlist();
    iniciarJobBlockchainSync();
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
      // FIX (auditoría 2026-09-27, A1): antes este `where` no miraba la disputa
      // en absoluto — si el cuidador simplemente no respondía a una disputa
      // abierta por el cliente, este job igual lo pagaba a las 72h (y si el
      // cuidador respondía después, resolveAndApplyDispute fallaba con
      // "ya no está ON_HOLD"/DISPUTE_ALREADY_RESOLVED). Ahora se excluyen las
      // reservas con una disputa activa (esperando respuesta o evaluación) —
      // esas dejan que el propio flujo de disputas (con su límite de
      // apelación de 5 días hábiles) decida, en vez de que este timer genérico
      // las pise a favor del cuidador por defecto.
      const stuckBookings = await prisma.booking.findMany({
        where: {
          status: 'COMPLETED',
          payoutStatus: 'ON_HOLD',
          ownerRated: true,
          updatedAt: { lte: cutoff },
          OR: [
            { dispute: null },
            { dispute: { status: { notIn: ['PENDING_CAREGIVER', 'PENDING_CLIENT', 'PENDING_AI', 'APPEALED'] } } },
          ],
        } as any,
        select: { id: true, caregiverId: true, totalAmount: true, commissionAmount: true, taxAmount: true },
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

            // FIX (auditoría 2026-09-27, A1): dos huecos más en el mismo job.
            // (1) `Number(booking.commissionAmount)` da 0 si commissionAmount
            // es null (reservas viejas sin ese campo poblado), pagando el
            // monto completo sin descontar la comisión de Garden — mismo
            // fallback ya usado en applyResolution (dispute.routes.ts).
            // (2) no creaba ningún WalletTransaction — el pago quedaba
            // invisible en el historial del cuidador. Se agrega, con el mismo
            // patrón de lock + balance real que el resto del proyecto.
            const amount = caregiverNetOf(booking);
            await tx.$queryRaw`SELECT id FROM "users" WHERE id = ${caregiverProfile.userId} FOR UPDATE`;
            const updated = await tx.user.update({
              where: { id: caregiverProfile.userId },
              data: { balance: { increment: amount } },
              select: { balance: true },
            });
            await tx.walletTransaction.create({
              data: {
                userId: caregiverProfile.userId,
                type: 'EARNING',
                amount,
                balance: Number(updated.balance),
                description: `Pago liberado automáticamente tras ${slaHoras}h sin resolución — reserva ${booking.id.slice(0, 8).toUpperCase()}`,
                bookingId: booking.id,
                status: 'COMPLETED',
              },
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

  // FIX (auditoría 2026-09-27, A6): una disputa de no-show (PENDING_CAREGIVER/
  // PENDING_CLIENT) no tenía ningún plazo si la otra parte nunca respondía —
  // quedaba retenida indefinidamente (dinero retenido, no perdido, pero sin
  // resolución posible: nadie puede forzar un veredicto sin la respuesta del
  // otro lado). Mismo criterio ya aplicado en A2/A3 de esta misma revisión:
  // ante algo que el pipeline automático no puede resolver con confianza
  // (acá, sin la versión de una de las partes), se escala a un admin para
  // revisión manual en vez de decidir un ganador por default — decidir "gana
  // quien sí respondió" sería premiar el orden de llegada, justo lo que el
  // propio prompt del juez de IA (dispute.routes.ts) advierte que NO es
  // evidencia de quién tiene razón.
  setInterval(async () => {
    try {
      const { getNumericSetting } = await import('./utils/settings-cache.js');
      const slaHoras = await getNumericSetting('disputeResponseSlaHoras', 72);
      const cutoff = new Date(Date.now() - slaHoras * 60 * 60 * 1000);
      const staleDisputes = await prisma.dispute.findMany({
        where: {
          status: { in: ['PENDING_CAREGIVER', 'PENDING_CLIENT'] },
          updatedAt: { lte: cutoff },
        } as any,
        select: { id: true, bookingId: true, status: true },
      });

      for (const dispute of staleDisputes as any[]) {
        try {
          // Idempotencia por consulta (sin campo nuevo en el schema): si ya se
          // notificó esta disputa, no se repite en la próxima corrida.
          const alreadyNotified = await prisma.adminNotification.findFirst({
            where: { type: 'DISPUTE_NO_RESPONSE', bookingId: dispute.bookingId },
          });
          if (alreadyNotified) continue;

          const booking = await prisma.booking.findUnique({
            where: { id: dispute.bookingId },
            select: { caregiverId: true },
          });

          await prisma.adminNotification.create({
            data: { type: 'DISPUTE_NO_RESPONSE', caregiverId: booking?.caregiverId ?? '', bookingId: dispute.bookingId },
          });

          const { sendPushToAdmins } = await import('./services/firebase.service.js');
          await sendPushToAdmins(
            '⏳ Disputa sin respuesta',
            `Reserva ${String(dispute.bookingId).slice(0, 8).toUpperCase()} — la otra parte no respondió en ${slaHoras}h. Requiere revisión manual (resolve-manual).`,
            { type: 'DISPUTE_NO_RESPONSE', bookingId: dispute.bookingId }
          ).catch(() => {});

          logger.warn('[SLA-DisputeNoResponse] Disputa sin respuesta — admin notificado', {
            disputeId: dispute.id,
            bookingId: dispute.bookingId,
            status: dispute.status,
          });
        } catch (err: any) {
          logger.error('[SLA-DisputeNoResponse] Failed to notify stale dispute', { disputeId: dispute.id, error: err.message });
        }
      }
    } catch (err: any) {
      logger.error('[SLA-DisputeNoResponse] Cron job failed', { error: err.message });
    }
  }, 6 * 60 * 60 * 1000); // Every 6 hours

  // Reactivación automática tras 30 días — suspensión por 3+ cancelaciones
  // tardías en 90 días (ver requestCancellationByCaregiver, booking.service.ts).
  // No se agregó una columna nueva al schema (suspendedUntil) porque no hay
  // forma de correr `prisma db push`/migrate contra producción desde esta
  // máquina ahora mismo (sin red hacia el Postgres de Render, y el Postgres
  // local de Docker tiene el bug de auth ya documentado en CLAUDE.md) — en vez
  // de eso, se calcula el vencimiento sobre campos que ya existen:
  // `suspendedAt` (seteado por suspendCaregiver en toda suspensión) +
  // `suspensionReason` exactamente igual a LATE_CANCELLATION_SUSPENSION_REASON
  // (identifica que ESTA suspensión puntual es de las que sí vencen solas —
  // una suspensión manual o por rating bajo con otro texto nunca matchea acá,
  // así que sigue siendo indefinida hasta que un admin la levante, como antes).
  setInterval(async () => {
    try {
      const { activateCaregiver, LATE_CANCELLATION_SUSPENSION_REASON } = await import('./modules/admin/admin.service.js');
      const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
      const expiredSuspensions = await prisma.caregiverProfile.findMany({
        where: {
          suspended: true,
          suspensionReason: LATE_CANCELLATION_SUSPENSION_REASON,
          suspendedAt: { lte: thirtyDaysAgo },
        },
        select: { id: true },
      });

      for (const profile of expiredSuspensions) {
        try {
          await activateCaregiver(
            profile.id,
            'SYSTEM_AUTO_REACTIVATE',
            'Suspensión temporal de 30 días por cancelaciones tardías vencida — reactivación automática.'
          );
          logger.info('[SLA-LateCancellationSuspension] Cuidador reactivado automáticamente tras 30 días', { profileId: profile.id });
        } catch (err: any) {
          logger.error('[SLA-LateCancellationSuspension] Failed to reactivate', { profileId: profile.id, error: err.message });
        }
      }
    } catch (err: any) {
      logger.error('[SLA-LateCancellationSuspension] Cron job failed', { error: err.message });
    }
  }, 6 * 60 * 60 * 1000); // Every 6 hours
}

start().catch(err => {
  logger.error('Fatal startup error', err);
  process.exit(1);
});
