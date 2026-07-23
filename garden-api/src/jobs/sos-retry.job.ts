/**
 * Job de reintento de aviso de SOS del cliente.
 *
 * reportClientSos() (booking.service.ts) ya manda un AdminNotification +
 * push urgente apenas el cliente reporta el SOS — pero si ningún admin lo ve
 * a tiempo, ese único aviso puede perderse entre el resto de notificaciones.
 * Es un caso de máxima gravedad (posible retención indebida de la mascota,
 * Sección 16 de Términos), así que no alcanza con avisar una sola vez.
 *
 * Corre cada 5 minutos: busca reservas IN_PROGRESS con el cronómetro
 * pausado (pausedAt no-null) cuyo último evento relevante sea CLIENT_SOS
 * (no un INCIDENT/ACCIDENT reportado por el cuidador — esos ya se resuelven
 * por otra vía), y reenvía el mismo aviso urgente. Se detiene solo:
 * resolveIncidentAdmin() pone pausedAt en null, sacando la reserva de esta
 * consulta en la próxima corrida — no hace falta ningún campo de "último
 * aviso enviado", el propio intervalo del cron ya da el espaciado.
 */

import cron from 'node-cron';
import { BookingStatus } from '@prisma/client';
import prisma from '../config/database.js';
import { sendPushToAdmins } from '../services/firebase.service.js';
import logger from '../shared/logger.js';

export function iniciarJobSosRetry() {
  cron.schedule('*/5 * * * *', async () => {
    await reintentarAvisosSosAbiertos();
  });
  logger.info('[SOS-RETRY JOB] Reintento de avisos de SOS sin resolver activo (cada 5 min).');
}

export async function reintentarAvisosSosAbiertos() {
  try {
    const candidatas = await prisma.booking.findMany({
      where: { status: BookingStatus.IN_PROGRESS, pausedAt: { not: null } },
      select: { id: true, serviceEvents: true, caregiverId: true },
    });

    for (const booking of candidatas) {
      const events = (booking.serviceEvents as any[]) || [];
      const lastRelevant = [...events].reverse().find(
        (e) => e.type === 'CLIENT_SOS' || e.type === 'INCIDENT' || e.type === 'ACCIDENT'
      );
      if (lastRelevant?.type !== 'CLIENT_SOS') continue;

      await prisma.adminNotification.create({
        data: { type: 'CLIENT_SOS_URGENT', caregiverId: booking.caregiverId, bookingId: booking.id },
      }).catch(() => {});
      await sendPushToAdmins(
        '🆘 SOS SIN RESOLVER — reintento',
        `Reserva ${booking.id.slice(0, 8).toUpperCase()} sigue con una alerta del dueño sin atender. ${lastRelevant.description ?? ''}`.slice(0, 180),
        { type: 'CLIENT_SOS_URGENT', bookingId: booking.id }
      ).catch(() => {});

      logger.warn('[SOS-RETRY JOB] Reintento de aviso enviado', { bookingId: booking.id });
    }
  } catch (err) {
    logger.error('[SOS-RETRY JOB] Error procesando reintentos de SOS', { err });
  }
}
