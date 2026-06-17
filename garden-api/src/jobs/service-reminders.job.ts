/**
 * Cron job que envía recordatorios a clientes y cuidadores antes del inicio del servicio.
 * Se ejecuta cada hora. Envía recordatorio a las 24h y a las 2h antes del servicio.
 */
import cron from 'node-cron';
import prisma from '../config/database.js';
import { onServiceReminder } from '../services/notification.service.js';
import { sendPushToUser } from '../services/firebase.service.js';
import logger from '../shared/logger.js';
import { autoPayoutExpiredReviews } from '../modules/booking-service/booking.service.js';

async function procesarRecordatoriosDeServicio() {
  const now = new Date();

  for (const hoursUntil of [24, 2]) {
    const windowStart = new Date(now.getTime() + (hoursUntil - 0.5) * 60 * 60 * 1000);
    const windowEnd = new Date(now.getTime() + (hoursUntil + 0.5) * 60 * 60 * 1000);

    const bookings = await prisma.booking.findMany({
      where: {
        status: 'CONFIRMED',
        OR: [
          { walkDate: { gte: windowStart, lte: windowEnd } },
          { startDate: { gte: windowStart, lte: windowEnd } },
        ],
      },
      select: {
        id: true,
        clientId: true,
        caregiver: { select: { userId: true } },
      },
    });

    if (bookings.length === 0) continue;

    for (const booking of bookings) {
      try {
        await onServiceReminder(booking.id, hoursUntil);

        const pushMsg = `Tu servicio empieza en ${hoursUntil === 24 ? '24 horas' : '2 horas'}. ¡Prepárate!`;
        sendPushToUser(booking.clientId, '⏰ Recordatorio de servicio', pushMsg).catch(() => {});
        if (booking.caregiver?.userId) {
          sendPushToUser(booking.caregiver.userId, '⏰ Recordatorio de servicio', pushMsg).catch(() => {});
        }

        logger.info(`[REMINDERS] Recordatorio ${hoursUntil}h enviado`, { bookingId: booking.id });
      } catch (err: any) {
        logger.error(`[REMINDERS] Error al enviar recordatorio`, { bookingId: booking.id, error: err.message });
      }
    }
  }
}

export function iniciarJobServiceReminders() {
  // Runs every hour at :00
  cron.schedule('0 * * * *', async () => {
    await procesarRecordatoriosDeServicio();
  });

  // Auto-payout: cada 4 horas libera pagos de servicios completados hace +48h sin calificar
  cron.schedule('0 */4 * * *', async () => {
    try {
      const count = await autoPayoutExpiredReviews();
      if (count > 0) logger.info(`[AutoPayout] ${count} desembolsos automáticos procesados`);
    } catch (err) {
      logger.error('[AutoPayout] Error en job de auto-payout', { err });
    }
  });

  logger.info('[REMINDERS] Job de recordatorios de servicio activo.');
}
