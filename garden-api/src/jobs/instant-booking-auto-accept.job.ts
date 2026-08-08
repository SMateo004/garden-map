/**
 * Job de "reserva instantánea" (≈ Instant Book de Airbnb).
 *
 * Corre cada minuto (mismo cadencia que qr-expiry.job.ts). Busca reservas
 * WAITING_CAREGIVER_APPROVAL cuyo cuidador activó instantBookingEnabled y
 * las acepta automáticamente, reusando acceptBooking() — el mismo código
 * que usa el cuidador al aceptar a mano, con las mismas notificaciones y la
 * misma transición atómica anti-doble-aceptación. No se duplica ninguna
 * lógica de negocio ni se toca el flujo de confirmación de pago (SIP/QR,
 * billetera, admin) en ningún punto — esos siguen dejando la reserva en
 * WAITING_CAREGIVER_APPROVAL exactamente igual que antes; este job solo
 * decide, un minuto después como máximo, si hace falta esperar al cuidador
 * o no.
 */

import cron from 'node-cron';
import { BookingStatus } from '@prisma/client';
import prisma from '../config/database.js';
import logger from '../shared/logger.js';
import { acceptBooking } from '../modules/booking-service/booking.service.js';

export function iniciarJobInstantBookingAutoAccept() {
  cron.schedule('* * * * *', async () => {
    await procesarReservasInstantaneas();
  });
  logger.info('[INSTANT-BOOKING JOB] Auto-aceptación de reserva instantánea activa.');
}

export async function procesarReservasInstantaneas() {
  try {
    const pendientes = await prisma.booking.findMany({
      where: {
        status: BookingStatus.WAITING_CAREGIVER_APPROVAL,
        caregiver: { instantBookingEnabled: true },
      },
      select: { id: true, caregiver: { select: { userId: true } } },
    });

    for (const booking of pendientes) {
      try {
        await acceptBooking(booking.id, booking.caregiver.userId);
        logger.info('[INSTANT-BOOKING JOB] Reserva auto-aceptada', { bookingId: booking.id });
      } catch (e: any) {
        // No detiene el resto del lote — puede ser una carrera con un
        // aceptar/rechazar manual simultáneo, que ya es válido y esperado.
        logger.warn('[INSTANT-BOOKING JOB] No se pudo auto-aceptar', {
          bookingId: booking.id, error: e?.message,
        });
      }
    }
  } catch (e: any) {
    logger.error('[INSTANT-BOOKING JOB] Error general', { error: e?.message });
  }
}
