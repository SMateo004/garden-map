/**
 * Pagos declarados por el cliente ("Ya realicé el pago").
 *
 * 1) Aprobación automática (cada minuto). Si el cliente declaró su pago y ningún admin lo
 *    aprobó ni rechazó antes de que venza la vigencia del QR (qrExpiresAt, 15 min por defecto),
 *    la reserva se aprueba sola y sigue su curso (verifyPaymentManual({ autoApproved })). Queda
 *    marcada para verificación posterior: el admin la confirma o, si el dinero no llegó, la
 *    marca como no recibida y se descuenta de la billetera del cliente
 *    (payment-review.service.ts). Regla definida con el founder, 2026-10-07.
 *
 * 2) Recordatorio (cada 10 minutos). Pagos sin verificar — aprobados automáticamente sin
 *    revisión, o pedidos de verificación manual en espera — que superan
 *    `paymentReviewAlertHoras` (12 h por defecto, Admin > Técnica) vuelven a avisarse a los
 *    admins, y otra vez cada ese mismo plazo. Solo avisa: nunca cancela ni toca dinero.
 */
import cron from 'node-cron';
import { BookingStatus, Prisma } from '@prisma/client';
import prisma from '../config/database.js';
import logger from '../shared/logger.js';
import { getNumericSetting } from '../utils/settings-cache.js';
import { sendPushToAdmins } from '../services/firebase.service.js';
import { verifyPaymentManual } from '../modules/payment-service/payment.service.js';

export const SETTING_PAYMENT_REVIEW_ALERT_HOURS = 'paymentReviewAlertHoras';
export const DEFAULT_PAYMENT_REVIEW_ALERT_HOURS = 12;
export const ADMIN_NOTIFICATION_PAYMENT_AUTO_APPROVED = 'PAYMENT_AUTO_APPROVED';
export const ADMIN_NOTIFICATION_PAYMENT_REVIEW_OVERDUE = 'PAYMENT_REVIEW_OVERDUE';

export function iniciarJobPaymentReview() {
  cron.schedule('* * * * *', async () => {
    await aprobarPagosDeclaradosVencidos();
  });
  cron.schedule('*/10 * * * *', async () => {
    await recordarPagosSinVerificar();
  });
  logger.info('[PAYMENT-REVIEW JOB] Aprobación automática de pagos declarados y recordatorios activos.');
}

/** Vigencia del QR en minutos (para reservas declaradas sin qrExpiresAt guardado). */
async function qrValidityMinutes(): Promise<number> {
  const m = await getNumericSetting('qrValidityMinutes', 15);
  return m > 0 && m <= 24 * 60 ? m : 15;
}

/** Plazo para volver a avisar, en horas (1–168); un valor inválido vuelve al default. */
export async function reviewWindowHours(): Promise<number> {
  const h = await getNumericSetting(SETTING_PAYMENT_REVIEW_ALERT_HOURS, DEFAULT_PAYMENT_REVIEW_ALERT_HOURS);
  return h >= 1 && h <= 168 ? h : DEFAULT_PAYMENT_REVIEW_ALERT_HOURS;
}

/** Pagos declarados cuya ventana (vigencia del QR) ya pasó sin que un admin los resolviera. */
export async function aprobarPagosDeclaradosVencidos(now: Date = new Date()): Promise<{ approved: string[] }> {
  const approved: string[] = [];
  try {
    const fallbackCutoff = new Date(now.getTime() - (await qrValidityMinutes()) * 60 * 1000);
    const due = await prisma.booking.findMany({
      where: {
        status: BookingStatus.PAYMENT_PENDING_APPROVAL,
        paymentDeclaredAt: { not: null },
        paidAt: null,
        OR: [{ qrExpiresAt: { lt: now } }, { qrExpiresAt: null, paymentDeclaredAt: { lt: fallbackCutoff } }],
      },
      select: { id: true, caregiverId: true },
    });

    for (const b of due) {
      try {
        await verifyPaymentManual(b.id, { autoApproved: true });
        await prisma.adminNotification.create({
          data: { type: ADMIN_NOTIFICATION_PAYMENT_AUTO_APPROVED, caregiverId: b.caregiverId, bookingId: b.id },
        });
        approved.push(b.id);
      } catch (err) {
        // Otro proceso (admin o banco) la resolvió en el medio: no es un error.
        logger.info('[PAYMENT-REVIEW] no se aprobó automáticamente (ya resuelta o cambió)', { bookingId: b.id, err });
      }
    }

    if (approved.length > 0) {
      await sendPushToAdmins(
        '✅ Pago aprobado automáticamente',
        approved.length === 1
          ? `Reserva ${approved[0]!.slice(0, 8).toUpperCase()}: nadie revisó el pago declarado a tiempo y se aprobó sola. Verifica si el dinero llegó.`
          : `${approved.length} reservas se aprobaron solas con el pago declarado. Verifica si el dinero llegó.`
      ).catch(() => {});
      logger.warn('[PAYMENT-REVIEW] pagos declarados aprobados automáticamente — pendientes de verificación', { bookings: approved });
    }
  } catch (err) {
    logger.error('[PAYMENT-REVIEW] aprobación automática falló', { err });
  }
  return { approved };
}

/** Recordatorio a los admins de pagos que siguen sin verificar pasado el plazo. */
export async function recordarPagosSinVerificar(now: Date = new Date()): Promise<{ alerted: number }> {
  try {
    const hours = await reviewWindowHours();
    const cutoff = new Date(now.getTime() - hours * 3600 * 1000);
    const notRecentlyAlerted: Prisma.BookingWhereInput = {
      OR: [{ paymentReviewAlertedAt: null }, { paymentReviewAlertedAt: { lt: cutoff } }],
    };
    const overdueWhere: Prisma.BookingWhereInput = {
      AND: [
        notRecentlyAlerted,
        {
          OR: [
            // Aprobada automáticamente y todavía sin verificar.
            { paymentAutoApprovedAt: { lt: cutoff }, paymentReviewedAt: null },
            // Pedido de verificación manual (sin aprobación automática) en espera.
            { status: BookingStatus.PAYMENT_PENDING_APPROVAL, paymentDeclaredAt: null, paymentApprovalRequestedAt: { lt: cutoff } },
          ],
        },
      ],
    };

    const overdue = await prisma.booking.findMany({ where: overdueWhere, select: { id: true, caregiverId: true } });
    if (overdue.length === 0) return { alerted: 0 };

    const alertedIds: string[] = [];
    for (const b of overdue) {
      try {
        const marked = await prisma.booking.updateMany({
          where: { AND: [{ id: b.id }, overdueWhere] },
          data: { paymentReviewAlertedAt: now },
        });
        if (marked.count === 0) continue;
        await prisma.adminNotification.create({
          data: { type: ADMIN_NOTIFICATION_PAYMENT_REVIEW_OVERDUE, caregiverId: b.caregiverId, bookingId: b.id },
        });
        alertedIds.push(b.id);
      } catch (err) {
        logger.error('[PAYMENT-REVIEW] no se pudo registrar el recordatorio', { bookingId: b.id, err });
      }
    }

    if (alertedIds.length > 0) {
      const n = alertedIds.length;
      await sendPushToAdmins(
        '⏰ Pagos sin verificar',
        n === 1
          ? `La reserva ${alertedIds[0]!.slice(0, 8).toUpperCase()} lleva más de ${hours} h con el pago sin verificar.`
          : `${n} reservas llevan más de ${hours} h con el pago sin verificar. Revísalas en Pagos pendientes.`
      ).catch(() => {});
      logger.warn('[PAYMENT-REVIEW] pagos sin verificar — admins avisados', { bookings: alertedIds, hours });
    }
    return { alerted: alertedIds.length };
  } catch (err) {
    logger.error('[PAYMENT-REVIEW] recordatorio falló', { err });
    return { alerted: 0 };
  }
}
