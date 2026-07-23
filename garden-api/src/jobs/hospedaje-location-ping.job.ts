/**
 * Cada hora, le pide al celular del cuidador un punto de ubicación puntual
 * para cada reserva de Hospedaje/Guardería en curso — vía push silencioso
 * (data-only, sin notificación visible). La app responde con
 * POST /bookings/:id/location-ping (ver recordHospedajeLocationPing en
 * booking.service.ts).
 *
 * A diferencia del GPS de Paseo (tracking continuo con mapa en vivo), esto
 * es solo trazabilidad de auditoría de seguridad — no hay sesión de
 * foreground service ni indicador visible para el cuidador. La entrega del
 * push en iOS es best-effort (Apple no garantiza el minuto exacto); Android
 * es más confiable. Ver Sección 7/27 de Términos y Condiciones para el
 * disclosure correspondiente.
 */

import cron from 'node-cron';
import { BookingStatus, ServiceType } from '@prisma/client';
import prisma from '../config/database.js';
import { sendSilentDataPush } from '../services/firebase.service.js';
import logger from '../shared/logger.js';

export function iniciarJobHospedajeLocationPing() {
  cron.schedule('0 * * * *', async () => {
    await enviarPingsDeUbicacion();
  });
  logger.info('[HOSPEDAJE-LOCATION-PING JOB] Ping horario de ubicación activo.');
}

async function enviarPingsDeUbicacion() {
  try {
    const bookings = await prisma.booking.findMany({
      where: {
        status: BookingStatus.IN_PROGRESS,
        serviceType: { in: [ServiceType.HOSPEDAJE, ServiceType.GUARDERIA] },
      },
      select: {
        id: true,
        caregiver: { select: { user: { select: { fcmToken: true } } } },
      },
    });

    if (bookings.length === 0) return;

    let sent = 0;
    for (const booking of bookings) {
      const fcmToken = (booking as any).caregiver?.user?.fcmToken;
      if (!fcmToken) continue;
      await sendSilentDataPush(fcmToken, {
        type: 'LOCATION_PING_REQUEST',
        bookingId: booking.id,
      });
      sent++;
    }

    logger.info('[HOSPEDAJE-LOCATION-PING JOB] Pings enviados', { total: bookings.length, sent });
  } catch (err) {
    logger.error('[HOSPEDAJE-LOCATION-PING JOB] Error procesando pings', { err });
  }
}
