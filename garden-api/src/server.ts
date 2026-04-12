import { createServer } from 'http';
import app from './app.js';
import { env } from './config/env.js';
import prisma from './config/database.js';
import logger from './shared/logger.js';
import { iniciarJobAjustePrecios } from './jobs/ajuste-precios.job.js';

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

  // Defer heavy background jobs by 10s to let the API warm up
  setTimeout(() => {
    logger.info('Starting background jobs (Pricing dynamic adjustment)...');
    iniciarJobAjustePrecios();
  }, 10000);

  // Auto-release payment 24h after service ends if owner hasn't reviewed
  // Runs every hour, processes any bookings past the 24h window
  setInterval(async () => {
    try {
      const { confirmReceiptByClient } = await import('./modules/booking-service/booking.service.js');
      const cutoff = new Date(Date.now() - 24 * 60 * 60 * 1000);
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
          await confirmReceiptByClient(booking.id, booking.clientId, 3, 'Auto-liberación tras 24h sin reseña');
          logger.info('[AutoRelease] Booking auto-released after 24h', { bookingId: booking.id });
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
