/**
 * Job de expiración de reservas SLOT_CONFLICT sin resolver.
 *
 * Corre cada 4 horas. Cuando dos clientes pagan el mismo horario, la segunda
 * reserva confirmada queda en SLOT_CONFLICT: el pago YA fue aceptado (el
 * dinero está retenido), y el cliente debe entrar a la app para elegir una
 * nueva fecha (resolveSlotConflict) o pedir reembolso. Si el cliente nunca
 * abre la app o ignora la notificación push, el dinero quedaba atrapado
 * indefinidamente — sin este job, no existía ningún mecanismo de respaldo.
 *
 * Regla: si una reserva lleva más de 72 horas en SLOT_CONFLICT, se cancela
 * y se reembolsa automáticamente — mismo patrón que rejectBooking(): la
 * porción pagada con billetera se devuelve al instante, la porción pagada
 * por QR queda PENDING_APPROVAL para que un admin la procese (no se puede
 * revertir un pago bancario sin intervención humana).
 */

import cron from 'node-cron';
import { BookingStatus, RefundStatus, Prisma } from '@prisma/client';
import prisma from '../config/database.js';
import { sendPushToUser } from '../services/firebase.service.js';
import logger from '../shared/logger.js';

const GRACE_PERIOD_MS = 72 * 60 * 60 * 1000; // 72h sin resolver

export function iniciarJobSlotConflictExpiry() {
  cron.schedule('0 */4 * * *', async () => {
    await procesarSlotConflictsExpirados();
  });
  logger.info('[SLOT-CONFLICT-EXPIRY JOB] Monitor de conflictos de horario sin resolver activo.');
}

export async function procesarSlotConflictsExpirados() {
  try {
    const cutoff = new Date(Date.now() - GRACE_PERIOD_MS);

    const candidatas = await prisma.booking.findMany({
      where: {
        status: BookingStatus.SLOT_CONFLICT,
        updatedAt: { lt: cutoff },
      },
      select: {
        id: true,
        clientId: true,
        caregiverId: true,
        petName: true,
        totalAmount: true,
        walletPaymentAmount: true,
      },
    });

    if (candidatas.length === 0) return;

    logger.info(`[SLOT-CONFLICT-EXPIRY] ${candidatas.length} reserva(s) SLOT_CONFLICT sin resolver a expirar`);

    for (const booking of candidatas) {
      try {
        await _expirarSlotConflict(booking);
      } catch (err) {
        logger.error('[SLOT-CONFLICT-EXPIRY] Error procesando booking', { bookingId: booking.id, err });
      }
    }
  } catch (err) {
    logger.error('[SLOT-CONFLICT-EXPIRY] Job fallido', { err });
  }
}

async function _expirarSlotConflict(booking: {
  id: string;
  clientId: string;
  caregiverId: string;
  petName: string;
  totalAmount: Prisma.Decimal;
  walletPaymentAmount: Prisma.Decimal | null;
}): Promise<void> {
  await prisma.$transaction(async (tx) => {
    // Guard contra race condition: solo actualizar si sigue en SLOT_CONFLICT
    // (el cliente pudo haberlo resuelto justo antes de que corriera el job)
    const result = await tx.booking.updateMany({
      where: { id: booking.id, status: BookingStatus.SLOT_CONFLICT },
      data: {
        status: BookingStatus.CANCELLED,
        cancelledAt: new Date(),
        cancellationReason: 'Conflicto de horario sin resolver por el cliente — cancelado automáticamente',
        refundStatus: RefundStatus.PENDING_APPROVAL,
        refundAmount: booking.totalAmount,
      },
    });
    if (result.count === 0) return; // ya lo resolvió el cliente

    const walletPaid = Number(booking.walletPaymentAmount ?? 0);
    let walletRefundNote = '';
    if (walletPaid > 0) {
      const updatedClient = await tx.user.update({
        where: { id: booking.clientId },
        data: { balance: { increment: walletPaid } },
        select: { balance: true },
      });
      await tx.walletTransaction.create({
        data: {
          userId: booking.clientId,
          type: 'REFUND',
          amount: walletPaid,
          balance: Number(updatedClient.balance),
          description: `Reembolso automático — conflicto de horario sin resolver (${booking.id.slice(0, 8)})`,
          bookingId: booking.id,
          status: 'COMPLETED',
        },
      });
      await tx.booking.update({ where: { id: booking.id }, data: { walletPaymentAmount: 0 } });
      walletRefundNote = ` Se reembolsaron Bs ${walletPaid.toFixed(2)} a tu billetera Garden automáticamente.`;
    }

    await tx.notification.create({
      data: {
        userId: booking.clientId,
        title: 'Reserva cancelada',
        message: `Tu reserva de ${booking.petName} tenía un conflicto de horario que no resolviste a tiempo — se canceló automáticamente.${walletRefundNote} El equipo de GARDEN gestionará el resto del reembolso en 1 día hábil.`,
        type: 'BOOKING_CANCELLED',
      },
    });

    await tx.adminNotification.create({
      data: {
        type: 'BOOKING_REJECTED_REFUND_NEEDED',
        caregiverId: booking.caregiverId,
        bookingId: booking.id,
      },
    });
  });

  sendPushToUser(
    booking.clientId,
    'Reserva cancelada',
    'Tu reserva con conflicto de horario se canceló automáticamente. Revisa tu reembolso en la app.'
  ).catch(() => {});

  logger.info('[SLOT-CONFLICT-EXPIRY] Reserva cancelada automáticamente', { bookingId: booking.id });
}
