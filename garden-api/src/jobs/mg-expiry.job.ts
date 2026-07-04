/**
 * Job de expiración de reservas PENDING_MG sin Meet & Greet aceptado.
 *
 * Corre cada hora. Antes de este job, una reserva creada con mgData (porque
 * el cuidador exige Meet & Greet) podía quedar en PENDING_MG para siempre si
 * ninguna de las partes actuaba manualmente: proceedToPayment() y
 * cancelMGBooking() existen, pero ambas requieren que el cliente o el
 * cuidador las llamen explícitamente — si nadie lo hace, la reserva bloquea
 * el slot de disponibilidad del cuidador indefinidamente.
 *
 * Regla: si el Meet & Greet propuesto nunca fue aceptado (status distinto de
 * ACCEPTED) y su proposedDate pasó hace más de 24 horas, se cancela la
 * reserva automáticamente. Nunca hay pago que reembolsar en este estado —
 * PENDING_MG es siempre anterior a cualquier intento de pago.
 */

import cron from 'node-cron';
import { BookingStatus, RefundStatus } from '@prisma/client';
import prisma from '../config/database.js';
import logger from '../shared/logger.js';

const GRACE_PERIOD_MS = 24 * 60 * 60 * 1000; // 24h después de la fecha propuesta

export function iniciarJobMgExpiry() {
  cron.schedule('0 * * * *', async () => {
    await procesarPendingMgExpirados();
  });
  logger.info('[MG-EXPIRY JOB] Monitor de reservas PENDING_MG sin resolver activo.');
}

export async function procesarPendingMgExpirados() {
  try {
    const cutoff = new Date(Date.now() - GRACE_PERIOD_MS);

    const candidatas = await prisma.booking.findMany({
      where: {
        status: BookingStatus.PENDING_MG,
        meetAndGreet: {
          status: { not: 'ACCEPTED' },
          proposedDate: { lt: cutoff },
        },
      },
      select: {
        id: true,
        clientId: true,
        caregiverId: true,
        caregiver: { select: { userId: true } },
      },
    });

    if (candidatas.length === 0) return;

    logger.info(`[MG-EXPIRY] ${candidatas.length} reserva(s) PENDING_MG sin resolver a expirar`);

    for (const booking of candidatas) {
      try {
        await _expirarPendingMg(booking);
      } catch (err) {
        logger.error('[MG-EXPIRY] Error procesando booking', { bookingId: booking.id, err });
      }
    }
  } catch (err) {
    logger.error('[MG-EXPIRY] Job fallido', { err });
  }
}

async function _expirarPendingMg(booking: {
  id: string;
  clientId: string;
  caregiverId: string;
  caregiver: { userId: string };
}): Promise<void> {
  await prisma.$transaction(async (tx) => {
    // Guard contra race condition: solo actualizar si aún está PENDING_MG
    const updated = await tx.booking.updateMany({
      where: { id: booking.id, status: BookingStatus.PENDING_MG },
      data: {
        status: BookingStatus.CANCELLED,
        cancelledAt: new Date(),
        cancellationReason: 'Meet & Greet no fue aceptado a tiempo — reserva cancelada automáticamente',
        refundAmount: 0,
        refundStatus: RefundStatus.REJECTED,
      },
    });
    if (updated.count === 0) return; // ya la resolvió alguien manualmente

    await tx.meetAndGreet.updateMany({
      where: { bookingId: booking.id, status: { not: 'ACCEPTED' } },
      data: { status: 'CANCELLED' },
    });

    await tx.notification.createMany({
      data: [
        {
          userId: booking.clientId,
          title: 'Reserva cancelada',
          message: 'Tu propuesta de Meet & Greet no fue aceptada a tiempo — la reserva se canceló automáticamente. No se realizó ningún cobro.',
          type: 'BOOKING_CANCELLED',
        },
        {
          userId: booking.caregiver.userId,
          title: 'Reserva cancelada',
          message: 'Una solicitud de reserva con Meet & Greet pendiente se canceló automáticamente por falta de respuesta.',
          type: 'BOOKING_CANCELLED',
        },
      ],
    });
  });

  logger.info('[MG-EXPIRY] Reserva PENDING_MG cancelada automáticamente', { bookingId: booking.id });
}
