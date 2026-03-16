import app from './app.js';
import { env } from './config/env.js';
import prisma from './config/database.js';
import logger from './shared/logger.js';
import { iniciarJobAjustePrecios } from './jobs/ajuste-precios.job.js';

// En desarrollo forzar 3000 para que el frontend (VITE_API_URL) conecte sin errores
const PORT =
  process.env.NODE_ENV !== 'production'
    ? 3000
    : (parseInt(env.PORT, 10) || 3000);

async function start() {
  try {
    await prisma.$connect();
    logger.info('Database connected');
  } catch (e) {
    logger.error('Database connection failed', e);
    process.exit(1);
  }

  // Fail fast if schema is out of sync (missing table or profilePhoto column)
  try {
    await prisma.caregiverProfile.findFirst({
      select: { id: true, profilePhoto: true },
      take: 1,
    });
  } catch (e: unknown) {
    const err = e as { code?: string; message?: string };
    const msg = typeof err?.message === 'string' ? err.message : '';
    const tableMissing =
      (msg.includes('caregiver_profiles') && (msg.includes('does not exist') || msg.includes('not exist'))) ||
      (msg.includes('table') && msg.includes('does not exist'));
    const columnMissing = err?.code === 'P2022' || msg.includes('profilePhoto');
    if (tableMissing || columnMissing) {
      const fixMsg =
        'Database schema out of sync. Table or column missing. Run: cd garden-api && npx prisma db push';
      logger.error(fixMsg);
      console.error('\n*** ' + fixMsg + ' ***\n');
      process.exit(1);
    }
    throw e;
  }

  // Iniciar Jobs Background
  iniciarJobAjustePrecios();

  app.listen(PORT, () => {
    logger.info(`GARDEN API listening on port ${PORT}`);
  });
}

process.on('SIGTERM', async () => {
  await prisma.$disconnect();
  process.exit(0);
});

start();
