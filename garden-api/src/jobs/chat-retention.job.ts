/**
 * Job de retención de chat — borra los mensajes de reservas cuyo servicio
 * terminó hace más de 30 días.
 *
 * Corre una vez al día. El chat de una reserva ya no aparece en la UI del
 * cliente/cuidador una vez que la reserva sale de los estados activos
 * (WAITING_CAREGIVER_APPROVAL / CONFIRMED / IN_PROGRESS) — eso ya lo hace la
 * app hoy, solo oculta el botón "Abrir chat". Pero los mensajes seguían
 * existiendo indefinidamente en la base de datos (y el admin podía leerlos)
 * como respaldo en caso de reclamo. Regla de negocio: 30 días de respaldo
 * tras terminar el servicio, después se borran los mensajes (no la reserva,
 * ni la disputa, ni la reseña — solo ChatMessage).
 *
 * "Terminó" se define por estado:
 *  - COMPLETED  → serviceEndedAt (o updatedAt si por algún camino alterno
 *                 no se seteó)
 *  - CANCELLED  → cancelledAt (o updatedAt)
 *  - REJECTED_BY_CAREGIVER → updatedAt (no hay fecha de fin de servicio,
 *                 el rechazo ocurre siempre poco después de crear la reserva)
 * Reservas en estados activos (PENDING_*, CONFIRMED, IN_PROGRESS, etc.)
 * nunca se tocan — la relación entre las partes sigue vigente.
 */

import cron from 'node-cron';
import { BookingStatus } from '@prisma/client';
import prisma from '../config/database.js';
import logger from '../shared/logger.js';

const RETENTION_DAYS = 30;

export function iniciarJobChatRetention() {
  cron.schedule('0 3 * * *', async () => {
    await purgarChatsVencidos();
  });
  logger.info('[CHAT-RETENTION JOB] Limpieza diaria de chats vencidos activa.');
}

export async function purgarChatsVencidos(): Promise<number> {
  const cutoff = new Date(Date.now() - RETENTION_DAYS * 24 * 60 * 60 * 1000);

  try {
    const candidatas = await prisma.booking.findMany({
      where: {
        OR: [
          { status: BookingStatus.COMPLETED, serviceEndedAt: { lte: cutoff } },
          { status: BookingStatus.COMPLETED, serviceEndedAt: null, updatedAt: { lte: cutoff } },
          { status: BookingStatus.CANCELLED, cancelledAt: { lte: cutoff } },
          { status: BookingStatus.CANCELLED, cancelledAt: null, updatedAt: { lte: cutoff } },
          { status: BookingStatus.REJECTED_BY_CAREGIVER, updatedAt: { lte: cutoff } },
        ],
        messages: { some: {} }, // solo reservas que aún tienen mensajes por borrar
      },
      select: { id: true },
    });

    if (candidatas.length === 0) return 0;

    let totalDeleted = 0;
    for (const booking of candidatas) {
      try {
        const result = await prisma.chatMessage.deleteMany({ where: { bookingId: booking.id } });
        totalDeleted += result.count;
      } catch (err) {
        logger.error('[CHAT-RETENTION] Error borrando mensajes de una reserva', { bookingId: booking.id, err });
      }
    }

    logger.info(`[CHAT-RETENTION] ${candidatas.length} reserva(s) purgadas, ${totalDeleted} mensaje(s) eliminados`);
    return totalDeleted;
  } catch (err) {
    logger.error('[CHAT-RETENTION] Job fallido', { err });
    return 0;
  }
}
