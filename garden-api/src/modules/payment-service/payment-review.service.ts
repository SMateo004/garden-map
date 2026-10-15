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
 *   - INCOMPLETE    → llegó menos de lo que debía (oct 2026). Se descuenta de la billetera solo la
 *                     diferencia (lo que debía llegar − lo recibido), con las mismas reglas que
 *                     NOT_RECEIVED. Vale para cualquier pago ya aprobado (a mano o solo), así el
 *                     admin puede aprobar un pago incompleto y cobrar el resto de la billetera.
 * La reserva NO se cancela. NOT_RECEIVED solo aplica a reservas aprobadas automáticamente: si el
 * admin rechaza dentro de la ventana, rige rejectPayment() (vuelve a pendiente de pago, sin cargo).
 *
 * Dinero: User.balance es la única fuente de saldo; bloqueo de la fila del usuario y de la
 * reserva (SELECT … FOR UPDATE) dentro de la transacción, igual que el resto del sistema.
 */
import prisma from '../../config/database.js';
import logger from '../../shared/logger.js';
import { BadRequestError, NotFoundError } from '../../shared/errors.js';
import { sendPushToUser } from '../../services/firebase.service.js';
import { releasePendingTips } from '../booking-service/tip-release.service.js';

export type PaymentReviewOutcome = 'CONFIRMED' | 'NOT_RECEIVED' | 'INCOMPLETE';
export const WALLET_TX_PAYMENT_NOT_RECEIVED = 'PAYMENT_NOT_RECEIVED';
export const WALLET_TX_PAYMENT_INCOMPLETE = 'PAYMENT_INCOMPLETE';

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
  outcome: PaymentReviewOutcome,
  /** Solo INCOMPLETE: cuánto llegó de verdad por QR (Bs). */
  receivedAmount?: number
): Promise<{ bookingId: string; outcome: PaymentReviewOutcome; chargedAmount: number; clientBalance: number | null }> {
  if (outcome === 'INCOMPLETE' && !(receivedAmount != null && receivedAmount >= 0)) {
    throw new BadRequestError('Indica cuánto llegó.');
  }
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
        paidAt: true,
      },
    });
    if (!b) throw new NotFoundError('Reserva no encontrada');
    if (outcome === 'INCOMPLETE') {
      if (!b.paidAt) throw new BadRequestError('Primero aprueba el pago; después registra que llegó incompleto.');
    } else if (!b.paymentAutoApprovedAt) {
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

    // Lo que debía llegar por QR + la deuda previa que la aprobación saldó
    // (applyConfirmedPaymentEffects): si el dinero no llegó, esa deuda vuelve.
    // Sin esto, aprobar solo un pago que nunca llegó borraba la deuda gratis.
    const recoveredDebt = await tx.walletTransaction.aggregate({
      where: { bookingId, userId: b.clientId, type: 'DEBT_RECOVERY' },
      _sum: { amount: true },
    });
    const due = amountExpectedByQr(b) + Number(recoveredDebt._sum.amount ?? 0);
    const received = outcome === 'INCOMPLETE' ? Number(receivedAmount) : 0;
    const charge = Math.max(0, Math.round((due - received) * 100) / 100);
    const incomplete = outcome === 'INCOMPLETE';
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
          type: incomplete ? WALLET_TX_PAYMENT_INCOMPLETE : WALLET_TX_PAYMENT_NOT_RECEIVED,
          amount: charge,
          balance: balanceAfter,
          description: incomplete
            ? `Pago incompleto — reserva ${bookingId.slice(0, 8).toUpperCase()}: llegaron Bs ${received.toFixed(2)} de Bs ${due.toFixed(2)}. Se descuenta la diferencia de tu billetera.`
            : `Pago no recibido — reserva ${bookingId.slice(0, 8).toUpperCase()}. Se descuenta de tu billetera.`,
          bookingId,
          status: 'COMPLETED',
        },
      });
    }
    await tx.booking.update({
      where: { id: bookingId },
      data: {
        paymentReviewedAt: now,
        paymentReviewOutcome: outcome,
        paymentReviewedBy: adminId,
        paymentChargedBackAmount: charge,
      },
    });
    if (charge > 0) await tx.notification.create({
      data: {
        bookingId,
        userId: b.clientId,
        title: 'Tienes un pago pendiente',
        message:
          (incomplete
            ? `Tu pago de la reserva ${bookingId.slice(0, 8).toUpperCase()} llegó incompleto (Bs ${received.toFixed(2)} de Bs ${due.toFixed(2)}). `
            : `No recibimos el pago de tu reserva ${bookingId.slice(0, 8).toUpperCase()}. `) +
          `Descontamos Bs ${charge.toFixed(2)} de tu billetera` +
          (balanceAfter !== null && balanceAfter < 0
            ? `; queda un saldo pendiente de Bs ${Math.abs(balanceAfter).toFixed(2)} que se cobrará en tu próximo pago.`
            : '.'),
        type: incomplete ? WALLET_TX_PAYMENT_INCOMPLETE : WALLET_TX_PAYMENT_NOT_RECEIVED,
      },
    });
    await tx.adminAction.create({
      data: {
        adminId,
        actionType: incomplete ? 'PAYMENT_REVIEW_INCOMPLETE' : 'PAYMENT_REVIEW_NOT_RECEIVED',
        targetId: bookingId,
        notes: incomplete
          ? `Pago incompleto: llegaron Bs ${received.toFixed(2)} de Bs ${due.toFixed(2)}. Descontado Bs ${charge.toFixed(2)} de la billetera del cliente. Booking ${bookingId}`
          : `Pago aprobado automáticamente NO llegó. Descontado Bs ${charge.toFixed(2)} de la billetera del cliente. Booking ${bookingId}`,
      },
    });
    return { clientId: b.clientId, charged: charge, balance: balanceAfter };
  });

  if (outcome !== 'CONFIRMED' && result.charged > 0) {
    logger.warn('[PAGO] Pago no recibido o incompleto — diferencia cargada a la billetera', {
      bookingId,
      adminId,
      outcome,
      charged: result.charged,
      clientBalance: result.balance,
    });
    sendPushToUser(
      result.clientId,
      'Tienes un pago pendiente',
      outcome === 'INCOMPLETE'
        ? `Tu pago llegó incompleto. Descontamos la diferencia (Bs ${result.charged.toFixed(2)}) de tu billetera.`
        : `No recibimos el pago de tu reserva. Descontamos Bs ${result.charged.toFixed(2)} de tu billetera.`
    ).catch(() => {});
  } else if (outcome === 'CONFIRMED') {
    logger.info('[PAGO] Pago aprobado automáticamente verificado (llegó)', { bookingId, adminId });
    // Las propinas que esperaban esta verificación ya se pueden liberar.
    try {
      await prisma.$transaction((tx) => releasePendingTips(tx, result.clientId));
    } catch (err) {
      logger.error('[PAGO] No se pudieron liberar propinas tras verificar el pago', { bookingId, err });
    }
  }
  return { bookingId, outcome, chargedAmount: result.charged, clientBalance: result.balance };
}
