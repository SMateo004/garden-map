import { BookingStatus } from '@prisma/client';
import Stripe from 'stripe';
import prisma from '../../config/database.js';
import { stripe } from '../../config/stripe.js';
import { env } from '../../config/env.js';
import { BadRequestError, NotFoundError } from '../../shared/errors.js';
import logger from '../../shared/logger.js';
import * as notificationService from '../../services/notification.service.js';
import { blockchainService } from '../../services/blockchain.service.js';

/** Amount in DB is in Bolivianos (Bs). Stripe BOB uses centavos (1 Bs = 100 centavos). */
const BOB_TO_CENTAVOS = 100;

export async function createCheckoutSession(
  bookingId: string,
  successUrl: string,
  cancelUrl: string,
  clientId: string
): Promise<{ sessionId: string; url: string }> {
  if (!stripe) {
    throw new BadRequestError('Pagos no configurados (Stripe). Contacta soporte.');
  }

  const booking = await prisma.booking.findFirst({
    where: { id: bookingId, clientId },
    include: { caregiver: { include: { user: true } } },
  });

  if (!booking) {
    throw new NotFoundError('Reserva no encontrada');
  }
  if (booking.status !== BookingStatus.PENDING_PAYMENT) {
    throw new BadRequestError('Esta reserva no está pendiente de pago');
  }
  if (booking.paidAt) {
    throw new BadRequestError('Esta reserva ya fue pagada');
  }

  const totalBs = Number(booking.totalAmount);
  const amountCentavos = Math.round(totalBs * BOB_TO_CENTAVOS);
  if (amountCentavos < 100) {
    throw new BadRequestError('El monto mínimo es Bs 1.00');
  }

  const session = await stripe.checkout.sessions.create({
    mode: 'payment',
    payment_method_types: ['card'],
    currency: 'bob',
    line_items: [
      {
        price_data: {
          currency: 'bob',
          unit_amount: amountCentavos,
          product_data: {
            name: `GARDEN - Reserva ${booking.serviceType === 'HOSPEDAJE' ? 'Hospedaje' : 'Paseo'}`,
            description: `Cuidador: ${booking.caregiver.user.firstName} ${booking.caregiver.user.lastName}. Mascota: ${booking.petName}.`,
            images: booking.caregiver.photos.length ? [booking.caregiver.photos[0]!] : undefined,
          },
        },
        quantity: 1,
      },
    ],
    success_url: successUrl,
    cancel_url: cancelUrl,
    client_reference_id: bookingId,
    metadata: {
      bookingId,
      clientId,
    },
  });

  await prisma.booking.update({
    where: { id: bookingId },
    data: { stripeCheckoutSessionId: session.id },
  });

  logger.info('Stripe Checkout session created', { bookingId, sessionId: session.id });

  const url = session.url;
  if (!url) {
    throw new BadRequestError('No se pudo generar la URL de pago');
  }

  return { sessionId: session.id, url };
}

export async function handleCheckoutCompleted(
  session: Stripe.Checkout.Session,
  stripeEventId: string
): Promise<void> {
  // ── Idempotencia fuerte: verificar por Stripe Event ID ─────────────────────
  // Stripe puede reenviar el mismo evento si no recibió 200 a tiempo.
  // Guardamos el eventId con @unique para que el segundo intento falle silenciosamente.
  const alreadyProcessed = await prisma.booking.findFirst({
    where: { stripeEventId },
  });
  if (alreadyProcessed) {
    logger.info('Stripe webhook: evento ya procesado (idempotencia)', { stripeEventId, bookingId: alreadyProcessed.id });
    return;
  }

  const bookingId = session.client_reference_id ?? session.metadata?.bookingId;
  if (!bookingId) {
    logger.warn('Stripe webhook: checkout.session.completed without bookingId', {
      sessionId: session.id,
      stripeEventId,
    });
    return;
  }

  const booking = await prisma.booking.findUnique({
    where: { id: bookingId },
  });

  if (!booking) {
    logger.warn('Stripe webhook: booking not found', { bookingId, stripeEventId });
    return;
  }
  if (booking.paidAt) {
    logger.info('Stripe webhook: booking already paid (paidAt check)', { bookingId, stripeEventId });
    return;
  }

  const paymentIntentId =
    typeof session.payment_intent === 'string'
      ? session.payment_intent
      : session.payment_intent?.id;

  await prisma.booking.update({
    where: { id: bookingId },
    data: {
      status: BookingStatus.WAITING_CAREGIVER_APPROVAL,
      paidAt: new Date(),
      stripePaymentIntentId: paymentIntentId ?? undefined,
      stripeEventId, // ← persiste para idempotencia
    },
  });

  logger.info('Booking waiting for caregiver approval after Stripe payment', {
    bookingId,
    sessionId: session.id,
  });
  notificationService.onBookingWaitingApproval(bookingId).catch((err) => {
    logger.error('Notification onBookingWaitingApproval failed (Stripe)', { bookingId, err });
  });

  // Registro en Blockchain — guardar txHash para verificación
  blockchainService.createBookingOnChain(
    bookingId,
    booking.clientId,
    booking.caregiverId,
    Number(booking.totalAmount),
    booking.startDate || booking.walkDate || new Date(),
    booking.endDate || booking.walkDate || new Date(),
    booking.petName,
    booking.serviceType
  ).then(async (txHash) => {
    if (txHash) {
      await prisma.booking.update({ where: { id: bookingId }, data: { blockchainTxHash: txHash } });
      logger.info('[Blockchain] txHash saved to booking', { bookingId, txHash });
    }
  }).catch(err => {
    logger.error('Blockchain registration failed (Stripe)', { bookingId, err });
  });
}

/**
 * Verifica pago por QR (placeholder integración bancaria) y confirma la reserva.
 * Busca por qrId; si la reserva está PENDING_PAYMENT y el QR no expiró, marca CONFIRMED y paidAt.
 */
export async function verifyPaymentByQr(qrId: string): Promise<{ bookingId: string; status: string }> {
  const booking = await prisma.booking.findFirst({
    where: { qrId },
  });

  if (!booking) {
    logger.warn('Payment verify: booking not found for qrId', { qrId });
    throw new NotFoundError('Código QR no válido o reserva no encontrada');
  }
  if (booking.status !== BookingStatus.PENDING_PAYMENT) {
    throw new BadRequestError(
      booking.paidAt ? 'Esta reserva ya fue pagada' : `La reserva no está pendiente de pago (estado: ${booking.status})`
    );
  }
  if (booking.qrExpiresAt && booking.qrExpiresAt < new Date()) {
    logger.warn('Payment verify: QR expired', { bookingId: booking.id, qrId });
    throw new BadRequestError('El código QR ha expirado. Genera uno nuevo desde la reserva.');
  }

  await prisma.booking.update({
    where: { id: booking.id },
    data: {
      status: BookingStatus.WAITING_CAREGIVER_APPROVAL,
      paidAt: new Date(),
    },
  });

  logger.info('Booking waiting for caregiver approval via QR verify', { bookingId: booking.id, qrId });
  notificationService.onBookingWaitingApproval(booking.id).catch((err) => {
    logger.error('Notification onBookingWaitingApproval failed', { bookingId: booking.id, err });
  });

  // Registro en Blockchain — guardar txHash
  blockchainService.createBookingOnChain(
    booking.id,
    booking.clientId,
    booking.caregiverId,
    Number(booking.totalAmount),
    booking.startDate || booking.walkDate || new Date(),
    booking.endDate || booking.walkDate || new Date(),
    booking.petName,
    booking.serviceType
  ).then(async (txHash) => {
    if (txHash) {
      await prisma.booking.update({ where: { id: booking.id }, data: { blockchainTxHash: txHash } });
      logger.info('[Blockchain] txHash saved to booking', { bookingId: booking.id, txHash });
    }
  }).catch(err => {
    logger.error('Blockchain registration failed (QR)', { bookingId: booking.id, err });
  });

  return { bookingId: booking.id, status: BookingStatus.WAITING_CAREGIVER_APPROVAL };
}

/**
 * Verificación manual de pago por admin. Reserva debe estar PENDING_PAYMENT o PAYMENT_PENDING_APPROVAL.
 * Marca la reserva como CONFIRMED y registra paidAt.
 */
export async function verifyPaymentManual(
  bookingId: string
): Promise<{ bookingId: string; status: string }> {
  const booking = await prisma.booking.findUnique({
    where: { id: bookingId },
  });

  if (!booking) {
    logger.warn('Payment verify manual: booking not found', { bookingId });
    throw new NotFoundError('Reserva no encontrada');
  }
  if (booking.status !== BookingStatus.PENDING_PAYMENT && booking.status !== BookingStatus.PAYMENT_PENDING_APPROVAL) {
    throw new BadRequestError(
      booking.paidAt
        ? 'Esta reserva ya fue pagada'
        : `Solo se puede aprobar pago en reservas pendientes (estado actual: ${booking.status})`
    );
  }
  if (booking.paidAt) {
    throw new BadRequestError('Esta reserva ya tiene fecha de pago registrada');
  }

  await prisma.booking.update({
    where: { id: bookingId },
    data: {
      status: BookingStatus.WAITING_CAREGIVER_APPROVAL,
      paidAt: new Date(),
    },
  });

  logger.info('Pago aprobado manualmente por admin; esperando aprobación cuidador', { bookingId });
  notificationService.onBookingWaitingApproval(bookingId).catch((err) => {
    logger.error('Notification onBookingWaitingApproval failed', { bookingId, err });
  });

  // Registro en Blockchain — guardar txHash
  blockchainService.createBookingOnChain(
    bookingId,
    booking.clientId,
    booking.caregiverId,
    Number(booking.totalAmount),
    booking.startDate || booking.walkDate || new Date(),
    booking.endDate || booking.walkDate || new Date(),
    booking.petName,
    booking.serviceType
  ).then(async (txHash) => {
    if (txHash) {
      await prisma.booking.update({ where: { id: bookingId }, data: { blockchainTxHash: txHash } });
      logger.info('[Blockchain] txHash saved to booking', { bookingId, txHash });
    }
  }).catch(err => {
    logger.error('Blockchain registration failed (Manual)', { bookingId, err });
  });

  return { bookingId, status: BookingStatus.WAITING_CAREGIVER_APPROVAL };
}
