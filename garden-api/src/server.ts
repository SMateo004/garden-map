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
}

process.on('SIGTERM', async () => {
  await prisma.$disconnect();
  process.exit(0);
});

start().catch(err => {
  logger.error('Fatal startup error', err);
  process.exit(1);
});
