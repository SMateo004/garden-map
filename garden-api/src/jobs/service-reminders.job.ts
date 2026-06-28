/**
 * Cron job que envía recordatorios a clientes y cuidadores antes del inicio del servicio.
 * Se ejecuta cada hora. Envía recordatorio a las 24h y a las 2h antes del servicio.
 * También monitorea hospedajes activos cuya endDate se acerca o ya pasó.
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

// ── Aviso de fin de hospedaje ────────────────────────────────────────────────
// Corre cada hora. Avisa al cliente 24h antes y 2h antes de endDate.
// Si endDate ya pasó y el servicio sigue IN_PROGRESS, recuerda al cuidador concluirlo.

async function procesarAvisosFinHospedaje() {
  const now = new Date();

  // 1. Avisos preventivos: 24h y 2h antes del checkout
  for (const hoursUntil of [24, 2]) {
    const windowStart = new Date(now.getTime() + (hoursUntil - 0.5) * 60 * 60 * 1000);
    const windowEnd   = new Date(now.getTime() + (hoursUntil + 0.5) * 60 * 60 * 1000);

    const hospedajes = await prisma.booking.findMany({
      where: {
        status: 'IN_PROGRESS',
        serviceType: 'HOSPEDAJE',
        endDate: { gte: windowStart, lte: windowEnd },
      },
      select: {
        id: true, clientId: true, petName: true, endDate: true,
        caregiver: { select: { userId: true } },
      },
    });

    for (const b of hospedajes) {
      try {
        const label = hoursUntil === 24 ? '24 horas' : '2 horas';
        const title = `🏠 Hospedaje finaliza en ${label}`;
        const msg   = `El hospedaje de ${b.petName ?? 'tu mascota'} termina en ${label}. ¿Necesitas más días?`;

        await prisma.notification.create({
          data: { userId: b.clientId, title, message: msg, type: 'WALK_EXPIRY_WARNING' },
        });
        sendPushToUser(b.clientId, title, msg).catch(() => {});

        if (b.caregiver?.userId) {
          const caregiverTitle = `🏠 Hospedaje termina en ${label}`;
          const caregiverMsg   = `El hospedaje de ${b.petName ?? 'la mascota'} finaliza en ${label}. Prepara el resumen del servicio.`;
          sendPushToUser(b.caregiver.userId, caregiverTitle, caregiverMsg).catch(() => {});
        }

        logger.info(`[HOSPEDAJE-EXPIRY] Aviso ${label} enviado`, { bookingId: b.id });
      } catch (err: any) {
        logger.error('[HOSPEDAJE-EXPIRY] Error en aviso preventivo', { bookingId: b.id, error: err?.message });
      }
    }
  }

  // 2. Aviso de overdue: endDate ya pasó y el servicio no ha sido concluido
  const overdueWindow = new Date(now.getTime() - 2 * 60 * 60 * 1000); // hasta 2h atrás para no spamear
  const overdue = await prisma.booking.findMany({
    where: {
      status: 'IN_PROGRESS',
      serviceType: 'HOSPEDAJE',
      endDate: { lt: now, gte: overdueWindow },
    },
    select: {
      id: true, clientId: true, petName: true,
      caregiver: { select: { userId: true } },
      serviceEvents: true,
    },
  });

  for (const b of overdue) {
    // Solo notificar una vez por booking (evitar spam en cada ciclo)
    const events = (b.serviceEvents as any[]) ?? [];
    const alreadyNotified = events.some((e: any) => e.type === 'HOSPEDAJE_OVERDUE_NOTIFIED');
    if (alreadyNotified) continue;

    try {
      await prisma.booking.update({
        where: { id: b.id },
        data: {
          serviceEvents: [
            ...events,
            { type: 'HOSPEDAJE_OVERDUE_NOTIFIED', timestamp: new Date().toISOString() },
          ],
        },
      });

      const clientTitle = '📋 Hospedaje finalizado — confirma la recepción';
      const clientMsg   = `El período de hospedaje de ${b.petName ?? 'tu mascota'} ha terminado. El cuidador debe concluir el servicio pronto.`;
      await prisma.notification.create({
        data: { userId: b.clientId, title: clientTitle, message: clientMsg, type: 'WALK_EXPIRY_END' },
      });
      sendPushToUser(b.clientId, clientTitle, clientMsg).catch(() => {});

      if (b.caregiver?.userId) {
        const caregiverTitle = '⚠️ Hospedaje vencido — concluye el servicio';
        const caregiverMsg   = `El hospedaje de ${b.petName ?? 'la mascota'} ya terminó. Por favor sube las fotos y concluye el servicio en la app.`;
        await prisma.notification.create({
          data: { userId: b.caregiver.userId, title: caregiverTitle, message: caregiverMsg, type: 'WALK_EXPIRY_END' },
        });
        sendPushToUser(b.caregiver.userId, caregiverTitle, caregiverMsg).catch(() => {});
      }

      logger.info('[HOSPEDAJE-EXPIRY] Aviso overdue enviado', { bookingId: b.id });
    } catch (err: any) {
      logger.error('[HOSPEDAJE-EXPIRY] Error en aviso overdue', { bookingId: b.id, error: err?.message });
    }
  }
}

export function iniciarJobServiceReminders() {
  // Recordatorios de inicio de servicio — cada hora
  cron.schedule('0 * * * *', async () => {
    await procesarRecordatoriosDeServicio();
    await procesarAvisosFinHospedaje().catch(err =>
      logger.error('[HOSPEDAJE-EXPIRY] Job falló', { err })
    );
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

  logger.info('[REMINDERS] Job de recordatorios de servicio activo (incluye avisos fin de hospedaje).');
}
