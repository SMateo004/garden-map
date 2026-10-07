/**
 * Verificación posterior de un pago aprobado automáticamente.
 *
 * Regla (definida con el founder, 2026-10-07): si el cliente tocó "Ya realicé el pago" y ningún
 * admin revisó el pago dentro de la vigencia del QR, la reserva se aprueba sola
 * (payment-review.job.ts → verifyPaymentManual({ autoApproved })). El admin puede verificarla
 * después:
 *   - CONFIRMED     → el dinero llegó. Solo se registra.
 *   - NOT_RECEIVED  → el dinero no llegó. Se descuenta de la billetera del cliente lo que debía
 *                     haber llegado por QR (total − lo pagado con billetera + donación). El saldo
 *                     puede quedar negativo: es deuda y se cobra en su próximo pago (mismo
 *                     mecanismo que el cargo por tiempo extra). El cliente recibe un aviso.
 * La reserva NO se cancela. Esto solo aplica a reservas aprobadas automáticamente: si el admin
 * rechaza dentro de la ventana, rige rejectPayment() (vuelve a pendiente de pago, sin cargo).
 *
 * Dinero: User.balance es la única fuente de saldo; bloqueo de la fila del usuario y de la
 * reserva (SELECT … FOR UPDATE) dentro de la transacción, igual que el resto del sistema.
 */
import prisma from '../../config/database.js';
import logger from '../../shared/logger.js';
import { BadRequestError, NotFoundError } from '../../shared/errors.js';
import { sendPushToUser } from '../../services/firebase.service.js';

export type PaymentReviewOutcome = 'CONFIRMED' | 'NOT_RECEIVED';
export const WALLET_TX_PAYMENT_NOT_RECEIVED = 'PAYMENT_NOT_RECEIVED';

/**
 * Lo que debía llegar por QR. Se guarda al declarar el pago (paymentExpectedAmount: incluye
 * todos los días de una guardería de varios días); si falta, total − billetera + donación.
 */
export function amountExpectedByQr(b: {
  totalAmount: unknown;
  walletPaymentAmount: unknown;
  donationAmount: unknown;
  paymentExpectedAmount?: unknown;
}): number {
  if (b.paymentExpectedAmount !== null && b.paymentExpectedAmount !== undefined) {
    return Math.max(0, Math.round(Number(b.paymentExpectedAmount) * 100) / 100);
  }
  const v = Number(b.totalAmount) - Number(b.walletPaymentAmount ?? 0) + Number(b.donationAmount ?? 0);
  return Math.max(0, Math.round(v * 100) / 100);
}

export async function reviewAutoApprovedPayment(
  bookingId: string,
  adminId: string,
  outcome: PaymentReviewOutcome
): Promise<{ bookingId: string; outcome: PaymentReviewOutcome; chargedAmount: number; clientBalance: number | null }> {
  const result = await prisma.$transaction(async (tx) => {
    await tx.$queryRaw`SELECT id FROM "bookings" WHERE id = ${bookingId} FOR UPDATE`;
    const b = await tx.booking.findUnique({
      where: { id: bookingId },
      select: {
        id: true,
        clientId: true,
        totalAmount: true,
        walletPaymentAmount: true,
        donationAmount: true,
        paymentExpectedAmount: true,
        paymentAutoApprovedAt: true,
        paymentReviewedAt: true,
      },
    });
    if (!b) throw new NotFoundError('Reserva no encontrada');
    if (!b.paymentAutoApprovedAt) {
      throw new BadRequestError('Este pago no fue aprobado automáticamente: usa aprobar/rechazar pago.');
    }
    if (b.paymentReviewedAt) {
      throw new BadRequestError('Este pago ya fue verificado.');
    }
    const now = new Date();

    if (outcome === 'CONFIRMED') {
      await tx.booking.update({
        where: { id: bookingId },
        data: { paymentReviewedAt: now, paymentReviewOutcome: 'CONFIRMED', paymentReviewedBy: adminId },
      });
      await tx.adminAction.create({
        data: {
          adminId,
          actionType: 'PAYMENT_REVIEW_CONFIRMED',
          targetId: bookingId,
          notes: `Pago aprobado automáticamente verificado: el dinero llegó. Booking ${bookingId}`,
        },
      });
      return { clientId: b.clientId, charged: 0, balance: null as number | null };
    }

    const charge = amountExpectedByQr(b);
    let balanceAfter: number | null = null;
    if (charge > 0) {
      await tx.$queryRaw`SELECT id FROM "users" WHERE id = ${b.clientId} FOR UPDATE`;
      const updated = await tx.user.update({
        where: { id: b.clientId },
        data: { balance: { decrement: charge } },
        select: { balance: true },
      });
      balanceAfter = Number(updated.balance);
      await tx.walletTransaction.create({
        data: {
          userId: b.clientId,
          type: WALLET_TX_PAYMENT_NOT_RECEIVED,
          amount: charge,
          balance: balanceAfter,
          description: `Pago no recibido — reserva ${bookingId.slice(0, 8).toUpperCase()}. Se descuenta de tu billetera.`,
          bookingId,
          status: 'COMPLETED',
        },
      });
    }
    await tx.booking.update({
      where: { id: bookingId },
      data: {
        paymentReviewedAt: now,
        paymentReviewOutcome: 'NOT_RECEIVED',
        paymentReviewedBy: adminId,
        paymentChargedBackAmount: charge,
      },
    });
    await tx.notification.create({
      data: {
        bookingId,
        userId: b.clientId,
        title: 'Tienes un pago pendiente',
        message:
          `No recibimos el pago de tu reserva ${bookingId.slice(0, 8).toUpperCase()}. ` +
          `Descontamos Bs ${charge.toFixed(2)} de tu billetera` +
          (balanceAfter !== null && balanceAfter < 0
            ? `; queda un saldo pendiente de Bs ${Math.abs(balanceAfter).toFixed(2)} que se cobrará en tu próximo pago.`
            : '.'),
        type: WALLET_TX_PAYMENT_NOT_RECEIVED,
      },
    });
    await tx.adminAction.create({
      data: {
        adminId,
        actionType: 'PAYMENT_REVIEW_NOT_RECEIVED',
        targetId: bookingId,
        notes: `Pago aprobado automáticamente NO llegó. Descontado Bs ${charge.toFixed(2)} de la billetera del cliente. Booking ${bookingId}`,
      },
    });
    return { clientId: b.clientId, charged: charge, balance: balanceAfter };
  });

  if (outcome === 'NOT_RECEIVED') {
    logger.warn('[PAGO] Pago aprobado automáticamente no recibido — cargado a la billetera', {
      bookingId,
      adminId,
      charged: result.charged,
      clientBalance: result.balance,
    });
    sendPushToUser(
      result.clientId,
      'Tienes un pago pendiente',
      `No recibimos el pago de tu reserva. Descontamos Bs ${result.charged.toFixed(2)} de tu billetera.`
    ).catch(() => {});
  } else {
    logger.info('[PAGO] Pago aprobado automáticamente verificado (llegó)', { bookingId, adminId });
  }
  return { bookingId, outcome, chargedAmount: result.charged, clientBalance: result.balance };
}
