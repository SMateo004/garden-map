import { createServer } from 'http';
import app from './app.js';
import { env } from './config/env.js';
import prisma from './config/database.js';
import logger from './shared/logger.js';
import { iniciarJobAjustePrecios } from './jobs/ajuste-precios.job.js';
import { iniciarJobNotificacionesProgramadas } from './jobs/scheduled-notifications.job.js';

const PORT = parseInt(process.env.PORT ?? '3000', 10);

const httpServer = createServer(app);

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

process.on('SIGTERM', async () => {
  await prisma.$disconnect();
  process.exit(0);
});

start().catch(err => {
  logger.error('Fatal startup error', err);
  process.exit(1);
});
