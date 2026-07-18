/**
 * Job de no-show: cancela automáticamente una reserva CONFIRMED cuya hora de
 * inicio ya pasó hace más del período de gracia configurable
 * (`noShowGracePeriodMinutos`, default 30 min) sin que el cuidador haya
 * marcado "iniciar servicio" (startService → status IN_PROGRESS).
 *
 * Antes esto se quedaba en CONFIRMED indefinidamente sin que nadie hiciera
 * nada — el cliente/cuidador debían darse cuenta y cancelar a mano.
 *
 * Política aplicada: "no-show: sin reembolso" (sección 7 de Términos y
 * Condiciones) — el sistema no puede determinar automáticamente de quién fue
 * la culpa (cliente ausente vs. cuidador ausente), así que no se aplica
 * ninguna penalización automática al cuidador (a diferencia de
 * caregiver-accept-expiry, donde sí se sabe con certeza que el cuidador nunca
 * respondió). Si hay una disputa sobre quién no se presentó, se resuelve por
 * el sistema de disputas normal — este job solo libera la reserva y notifica
 * a ambas partes.
 */

import cron from 'node-cron';
import { BookingStatus, RefundStatus } from '@prisma/client';
import prisma from '../config/database.js';
import { getNumericSetting } from '../utils/settings-cache.js';
import { boliviaDateAndTimeToMs } from '../utils/bolivia-time.js';
import { sendPushToUser } from '../services/firebase.service.js';
import logger from '../shared/logger.js';

export function iniciarJobNoShowExpiry() {
  cron.schedule('*/5 * * * *', async () => {
    await procesarNoShows();
  });
  logger.info('[NO-SHOW-EXPIRY JOB] Monitor de reservas no-show activo.');
}

/**
 * Hora de inicio efectiva de la reserva, según el tipo de servicio.
 *
 * Bug real que esto corrige: antes usaba `Date.setHours()`, que interpreta
 * la hora en la zona horaria del PROCESO (UTC en Render) en vez de la de
 * Bolivia (UTC-4) — el cálculo quedaba 4 horas adelantado respecto al
 * reloj de Bolivia, así que para cuando el reloj de Bolivia llegaba a la
 * hora real de la reserva, el job ya la consideraba vencida hace rato y la
 * cancelaba en el primer tick del cron, ignorando por completo el período
 * de gracia configurado por el admin.
 */
function computeStartTime(booking: {
  serviceType: string;
  walkDate: Date | null;
  startTime: string | null;
  startDate: Date | null;
}): Date | null {
  if (booking.serviceType === 'HOSPEDAJE') {
    if (!booking.startDate) return null;
    return new Date(boliviaDateAndTimeToMs(booking.startDate));
  }
  // PASEO / GUARDERIA: walkDate + startTime ("HH:MM")
  if (!booking.walkDate) return null;
  return new Date(boliviaDateAndTimeToMs(booking.walkDate, booking.startTime ?? '00:00'));
}

export async function procesarNoShows() {
  try {
    const graciaMinutos = await getNumericSetting('noShowGracePeriodMinutos', 30);
    const now = new Date();

    const candidatas = await prisma.booking.findMany({
      where: { status: BookingStatus.CONFIRMED },
      select: {
        id: true,
        clientId: true,
        caregiverId: true,
        petName: true,
        serviceType: true,
        walkDate: true,
        startDate: true,
        startTime: true,
      },
    });

    if (candidatas.length === 0) return;

    for (const booking of candidatas) {
      try {
        const start = computeStartTime(booking);
        if (!start) continue; // sin fecha suficiente, no se puede evaluar — no tocar
        const minutosDesdeInicio = (now.getTime() - start.getTime()) / 60000;
        if (minutosDesdeInicio < graciaMinutos) continue; // todavía dentro de la ventana de gracia

        await _cancelarPorNoShow(booking);
      } catch (err) {
        logger.error('[NO-SHOW-EXPIRY] Error procesando booking', { bookingId: booking.id, err });
      }
    }
  } catch (err) {
    logger.error('[NO-SHOW-EXPIRY] Job fallido', { err });
  }
}

async function _cancelarPorNoShow(booking: {
  id: string;
  clientId: string;
  caregiverId: string;
  petName: string | null;
}): Promise<void> {
  const result = await prisma.$transaction(async (tx) => {
    // Guard contra race condition: solo actualizar si sigue CONFIRMED
    // (el cuidador pudo haber iniciado el servicio justo antes de que corriera el job).
    const updated = await tx.booking.updateMany({
      where: { id: booking.id, status: BookingStatus.CONFIRMED },
      data: {
        status: BookingStatus.CANCELLED,
        cancelledAt: new Date(),
        cancellationReason: 'El servicio no comenzó dentro del plazo acordado — cancelado automáticamente por no presentación (no-show)',
        cancellationSource: 'NO_SHOW',
        refundStatus: RefundStatus.REJECTED,
        refundAmount: 0,
      },
    });
    return updated.count > 0;
  });

  if (!result) return; // ya lo procesó el cuidador (inició el servicio) antes que este job

  await prisma.notification.createMany({
    data: [
      {
        userId: booking.clientId,
        title: 'Reserva cancelada por no presentación',
        message: `La reserva de ${booking.petName ?? 'tu mascota'} se canceló automáticamente porque el servicio no comenzó a tiempo. Según la política de no-show, no aplica reembolso. Si crees que esto es un error, contacta a soporte.`,
        type: 'BOOKING_CANCELLED',
      },
    ],
  });

  const caregiver = await prisma.caregiverProfile.findUnique({ where: { id: booking.caregiverId }, select: { userId: true } });
  if (caregiver) {
    await prisma.notification.create({
      data: {
        userId: caregiver.userId,
        title: 'Reserva cancelada por no presentación',
        message: `La reserva de ${booking.petName ?? 'la mascota'} se canceló automáticamente porque el servicio no comenzó a tiempo (no-show).`,
        type: 'BOOKING_CANCELLED',
      },
    });
    sendPushToUser(caregiver.userId, 'Reserva cancelada', 'Se canceló automáticamente por no presentación (no-show).').catch(() => {});
  }

  sendPushToUser(booking.clientId, 'Reserva cancelada', 'Se canceló automáticamente porque el servicio no comenzó a tiempo (no-show).').catch(() => {});

  logger.info('[NO-SHOW-EXPIRY] Reserva cancelada automáticamente por no-show', { bookingId: booking.id });
}
