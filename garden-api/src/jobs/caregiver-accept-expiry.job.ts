/**
 * Job de expiración de reservas WAITING_CAREGIVER_APPROVAL sin aceptar.
 *
 * Corre cada 10 minutos. Cuando el pago se confirma, la reserva queda en
 * WAITING_CAREGIVER_APPROVAL hasta que el cuidador la acepta o la rechaza.
 * Si el cuidador nunca responde, el dinero del cliente quedaba retenido
 * indefinidamente — este job cancela la reserva automáticamente pasado el
 * límite configurable (`caregiverAcceptWindowHoras`, default 3h) y reembolsa
 * el monto completo a la billetera del cliente de inmediato (a diferencia de
 * otras cancelaciones automáticas del sistema, acá no se deja la porción QR
 * pendiente de aprobación de admin — decisión de producto: el cuidador nunca
 * respondió, no hubo servicio, se devuelve todo sin fricción para el cliente).
 */

import cron from 'node-cron';
import { BookingStatus } from '@prisma/client';
import prisma from '../config/database.js';
import { getNumericSetting } from '../utils/settings-cache.js';
import { sendPushToUser } from '../services/firebase.service.js';
import logger from '../shared/logger.js';
import { staffUserIdsWithPermission } from '../modules/caregiver-staff/caregiver-staff.service.js';
import { boliviaDateAndTimeToMs } from '../utils/bolivia-time.js';

/**
 * Plazo para aceptar, en horas. Una empresa con empleados que pueden aceptar reservas (función
 * habilitada por el admin + al menos un empleado activo con el permiso) tiene el doble — antes el
 * aviso al equipo se agregó pero la reserva igual vencía a las 3 h (auditoría 2026-10-10, H1).
 */
export async function acceptWindowHoursFor(caregiverProfileId: string): Promise<{ hours: number; team: boolean }> {
  const base = await getNumericSetting('caregiverAcceptWindowHoras', 3);
  const team = (await staffUserIdsWithPermission(caregiverProfileId, 'canManageBookings').catch(() => [])).length > 0;
  return { hours: team ? base * 2 : base, team };
}

/** Cuándo empieza el servicio (hora de Bolivia), o null si no se puede saber. */
function serviceStartMs(b: { serviceType: string; startDate: Date | null; walkDate: Date | null; startTime: string | null }): number | null {
  if (b.serviceType === 'HOSPEDAJE') return b.startDate ? boliviaDateAndTimeToMs(b.startDate) : null;
  return b.walkDate ? boliviaDateAndTimeToMs(b.walkDate, b.startTime ?? undefined) : null;
}

export function iniciarJobCaregiverAcceptExpiry() {
  cron.schedule('*/10 * * * *', async () => {
    await procesarAceptacionesExpiradas();
  });
  logger.info('[CAREGIVER-ACCEPT-EXPIRY JOB] Monitor de reservas sin aceptar por el cuidador activo.');
}

export async function procesarAceptacionesExpiradas() {
  try {
    const ventanaHoras = await getNumericSetting('caregiverAcceptWindowHoras', 3);
    const cutoff = new Date(Date.now() - ventanaHoras * 60 * 60 * 1000);

    const vencidasBase = await prisma.booking.findMany({
      where: {
        status: BookingStatus.WAITING_CAREGIVER_APPROVAL,
        updatedAt: { lt: cutoff },
      },
      select: {
        id: true,
        clientId: true,
        caregiverId: true,
        petName: true,
        totalAmount: true,
        updatedAt: true,
        serviceType: true,
        startDate: true,
        walkDate: true,
        startTime: true,
      },
    });

    // Empresas con equipo: plazo doble, pero nunca más allá del inicio del servicio.
    const windowByCaregiver = new Map<string, number>();
    const candidatas: typeof vencidasBase = [];
    for (const b of vencidasBase) {
      let hours = windowByCaregiver.get(b.caregiverId);
      if (hours === undefined) {
        hours = (await acceptWindowHoursFor(b.caregiverId)).hours;
        windowByCaregiver.set(b.caregiverId, hours);
      }
      let deadline = b.updatedAt.getTime() + hours * 60 * 60 * 1000;
      const start = serviceStartMs(b);
      if (start !== null) deadline = Math.min(deadline, Math.max(start, b.updatedAt.getTime() + ventanaHoras * 60 * 60 * 1000));
      if (Date.now() >= deadline) candidatas.push(b);
    }

    if (candidatas.length === 0) return;

    logger.info(`[CAREGIVER-ACCEPT-EXPIRY] ${candidatas.length} reserva(s) sin aceptar a expirar (ventana: ${ventanaHoras}h)`);

    for (const booking of candidatas) {
      try {
        await _expirarAceptacion(booking);
      } catch (err) {
        logger.error('[CAREGIVER-ACCEPT-EXPIRY] Error procesando booking', { bookingId: booking.id, err });
      }
    }
  } catch (err) {
    logger.error('[CAREGIVER-ACCEPT-EXPIRY] Job fallido', { err });
  }
}

async function _expirarAceptacion(booking: {
  id: string;
  clientId: string;
  caregiverId: string;
  petName: string;
  totalAmount: import('@prisma/client').Prisma.Decimal;
}): Promise<void> {
  await prisma.$transaction(async (tx) => {
    // Guard contra race condition: solo actualizar si sigue esperando aceptación
    // (el cuidador pudo haber aceptado/rechazado justo antes de que corriera el job)
    const result = await tx.booking.updateMany({
      where: { id: booking.id, status: BookingStatus.WAITING_CAREGIVER_APPROVAL },
      data: {
        status: BookingStatus.REJECTED_BY_CAREGIVER,
        cancelledAt: new Date(),
        cancellationReason: 'El cuidador no respondió a la solicitud a tiempo — cancelado automáticamente',
        // Marca estructurada (distinta del texto libre de arriba) para poder
        // distinguir "nunca respondió" de "rechazó activamente" al calcular
        // la tasa de respuesta del perfil (ver getCaregiverTrustStats).
        cancellationSource: 'AUTO_EXPIRY_NO_RESPONSE',
        refundStatus: 'PROCESSED' as any,
        refundAmount: booking.totalAmount,
      },
    });
    if (result.count === 0) return; // ya lo procesó el cuidador

    const refundAmount = Number(booking.totalAmount);
    const updatedClient = await tx.user.update({
      where: { id: booking.clientId },
      data: { balance: { increment: refundAmount } },
      select: { balance: true },
    });
    await tx.walletTransaction.create({
      data: {
        userId: booking.clientId,
        type: 'REFUND',
        amount: refundAmount,
        balance: Number(updatedClient.balance),
        description: `Reembolso automático — el cuidador no respondió a tiempo (${booking.id.slice(0, 8)})`,
        bookingId: booking.id,
        status: 'COMPLETED',
      },
    });
    await tx.booking.update({ where: { id: booking.id }, data: { walletPaymentAmount: 0 } });

    await tx.notification.create({
      data: {
        bookingId: booking.id,
        userId: booking.clientId,
        title: 'Reserva cancelada',
        message: `El cuidador no respondió a tu solicitud para ${booking.petName} a tiempo, así que se canceló automáticamente. Se reembolsaron Bs ${refundAmount.toFixed(2)} a tu billetera Garden.`,
        type: 'BOOKING_REJECTED',
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
    'Reserva cancelada — reembolso',
    `El cuidador no respondió a tu solicitud para ${booking.petName}. Reembolsamos Bs ${Number(booking.totalAmount).toFixed(2)} a tu billetera Garden.`
  ).catch(() => {});

  logger.info('[CAREGIVER-ACCEPT-EXPIRY] Reserva cancelada automáticamente', { bookingId: booking.id });
}
