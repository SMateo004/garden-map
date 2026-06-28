import { BookingStatus } from '@prisma/client';
import Stripe from 'stripe';
import prisma from '../../config/database.js';
import { stripe } from '../../config/stripe.js';
import { env } from '../../config/env.js';
import { BadRequestError, NotFoundError } from '../../shared/errors.js';
import logger from '../../shared/logger.js';
import { track } from '../../shared/analytics.js';
import * as notificationService from '../../services/notification.service.js';
import { blockchainService } from '../../services/blockchain.service.js';
import { sendPushToUser } from '../../services/firebase.service.js';
import { confirmExtensionQrBySip } from '../booking-service/booking.service.js';

/** Amount in DB is in Bolivianos (Bs). Stripe BOB uses centavos (1 Bs = 100 centavos). */
const BOB_TO_CENTAVOS = 100;

/**
 * Derives the correct end date for a booking to pass to the blockchain.
 * For multi-day walks (walkDays JSON array), uses the last day in the array.
 * For hospedaje, uses endDate. Falls back to startDate / walkDate / now.
 */
function resolveBookingEndDate(booking: {
  startDate: Date | null;
  endDate: Date | null;
  walkDate: Date | null;
  walkDays?: unknown;
}): Date {
  // Multi-day PASEO: pick the last date from the walkDays array
  if (booking.walkDays && Array.isArray(booking.walkDays) && (booking.walkDays as any[]).length > 0) {
    const days = booking.walkDays as Array<{ date: string }>;
    const lastDay = days[days.length - 1];
    if (lastDay?.date) return new Date(lastDay.date);
  }
  // HOSPEDAJE or single-day PASEO
  return booking.endDate ?? booking.startDate ?? booking.walkDate ?? new Date();
}

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
            name: `GARDEN - Reserva ${booking.serviceType === 'HOSPEDAJE' ? 'Hospedaje' : booking.serviceType === 'GUARDERIA' ? 'Guardería por horas' : 'Paseo'}`,
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
  track(booking.clientId, 'payment_completed', {
    bookingId,
    method: 'stripe',
    amount: Number(booking.totalAmount),
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
    booking.startDate ?? booking.walkDate ?? new Date(),
    resolveBookingEndDate(booking),      // ← multi-day walk: last walkDay date
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
export async function verifyPaymentByQr(qrId: string, clientId: string): Promise<{ bookingId: string; status: string }> {
  // Ownership check: only the booking's own client can confirm their QR payment
  const booking = await prisma.booking.findFirst({
    where: { qrId, clientId },
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

  // Atomic status transition: only updates if still PENDING_PAYMENT (prevents race condition double-confirm)
  const updateResult = await prisma.booking.updateMany({
    where: { id: booking.id, status: BookingStatus.PENDING_PAYMENT },
    data: {
      status: BookingStatus.WAITING_CAREGIVER_APPROVAL,
      paidAt: new Date(),
    },
  });

  if (updateResult.count === 0) {
    // Another concurrent request already processed this QR
    throw new BadRequestError('Esta reserva ya fue pagada o el estado cambió. Actualiza la app.');
  }

  logger.info('Booking waiting for caregiver approval via QR verify', { bookingId: booking.id, qrId });
  track(booking.clientId, 'payment_completed', {
    bookingId: booking.id,
    method: 'qr',
    amount: Number(booking.totalAmount),
  });

  // ── Detección de conflicto de horario ────────────────────────────────────────
  // Si otro usuario ya confirmó/pagó la misma franja, marcar SLOT_CONFLICT.
  // El pago ya está aceptado; el dinero queda retenido hasta que el cliente elija nueva hora.
  let hasSlotConflict = false;
  try {
    const conflictStatuses = [
      BookingStatus.WAITING_CAREGIVER_APPROVAL,
      BookingStatus.CONFIRMED,
      BookingStatus.IN_PROGRESS,
    ];
    let conflictBooking = null;

    if (booking.serviceType === 'PASEO' && booking.walkDate && booking.timeSlot) {
      conflictBooking = await prisma.booking.findFirst({
        where: {
          id: { not: booking.id },
          caregiverId: booking.caregiverId,
          walkDate: booking.walkDate,
          timeSlot: booking.timeSlot,
          status: { in: conflictStatuses },
        },
      });
    } else if ((booking.serviceType === 'HOSPEDAJE' || booking.serviceType === 'GUARDERIA') && booking.startDate && booking.endDate) {
      conflictBooking = await prisma.booking.findFirst({
        where: {
          id: { not: booking.id },
          caregiverId: booking.caregiverId,
          serviceType: booking.serviceType,
          status: { in: conflictStatuses },
          startDate: { lte: booking.endDate },
          endDate: { gt: booking.startDate },
        },
      });
    }

    if (conflictBooking) {
      hasSlotConflict = true;
      await prisma.booking.update({
        where: { id: booking.id },
        data: { status: BookingStatus.SLOT_CONFLICT },
      });
      logger.warn('Slot conflict detected after payment', {
        bookingId: booking.id,
        conflictBookingId: conflictBooking.id,
        caregiverId: booking.caregiverId,
      });
      sendPushToUser(
        booking.clientId,
        'Tu hora fue reservada por otro usuario',
        'Tu pago está seguro. Abre la app para elegir una nueva hora disponible.'
      ).catch(() => {});
    }
  } catch (err) {
    logger.error('Slot conflict check failed (non-fatal)', { bookingId: booking.id, err });
  }

  if (!hasSlotConflict) {
    notificationService.onBookingWaitingApproval(booking.id).catch((err) => {
      logger.error('Notification onBookingWaitingApproval failed', { bookingId: booking.id, err });
    });
  }

  // Si el dueño eligió donar, registrar la donación
  if (booking.donationAmount && Number(booking.donationAmount) > 0) {
    prisma.donation.upsert({
      where: { bookingId: booking.id },
      create: { bookingId: booking.id, clientId: booking.clientId, amount: booking.donationAmount },
      update: {},
    }).catch((err) => logger.error('Donation record creation failed (QR)', { bookingId: booking.id, err }));
  }

  // Si había deuda previa incluida en el QR, recuperarla (zerificar balance negativo)
  const debtRecovery = Number((booking as any).debtRecoveryAmount ?? 0);
  if (debtRecovery > 0) {
    prisma.user.update({
      where: { id: booking.clientId },
      data: { balance: { increment: debtRecovery } },
    }).then(() => {
      return prisma.walletTransaction.create({
        data: {
          userId: booking.clientId,
          type: 'DEBT_RECOVERY',
          amount: debtRecovery,
          balance: 0, // balance se zerificó
          description: `Deuda por tiempo extra recuperada vía QR — reserva ${booking.id.slice(0, 8)}`,
          bookingId: booking.id,
          status: 'COMPLETED',
        },
      });
    }).catch((err) => logger.error('Debt recovery failed (QR)', { bookingId: booking.id, err }));
  }

  // Registro en Blockchain — guardar txHash
  blockchainService.createBookingOnChain(
    booking.id,
    booking.clientId,
    booking.caregiverId,
    Number(booking.totalAmount),
    booking.startDate ?? booking.walkDate ?? new Date(),
    resolveBookingEndDate(booking),
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

  return {
    bookingId: booking.id,
    status: hasSlotConflict ? BookingStatus.SLOT_CONFLICT : BookingStatus.WAITING_CAREGIVER_APPROVAL,
  };
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

  // Si el dueño eligió donar, registrar la donación (ignorar si ya existe por doble-tap)
  if (booking.donationAmount && Number(booking.donationAmount) > 0) {
    await prisma.donation.upsert({
      where: { bookingId },
      create: { bookingId, clientId: booking.clientId, amount: booking.donationAmount },
      update: {},
    }).catch((err) => logger.error('Donation record creation failed', { bookingId, err }));
  }

  logger.info('Pago aprobado manualmente por admin; esperando aprobación cuidador', { bookingId });
  track(booking.clientId, 'payment_completed', {
    bookingId,
    method: 'manual_admin',
    amount: Number(booking.totalAmount),
  });
  notificationService.onBookingWaitingApproval(bookingId).catch((err) => {
    logger.error('Notification onBookingWaitingApproval failed', { bookingId, err });
  });

  // Registro en Blockchain — guardar txHash
  blockchainService.createBookingOnChain(
    bookingId,
    booking.clientId,
    booking.caregiverId,
    Number(booking.totalAmount),
    booking.startDate ?? booking.walkDate ?? new Date(),
    resolveBookingEndDate(booking),      // ← multi-day walk: last walkDay date
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

/**
 * Confirmación de pago desde el callback de SIP (banco).
 * No requiere clientId — la autenticación es Basic Auth server-to-server.
 * El alias SIP equivale al bookingId de nuestra plataforma.
 */
export async function verifyPaymentBySipCallback(
  alias: string
): Promise<{ bookingId: string; status: string }> {
  const booking = await prisma.booking.findFirst({
    where: { id: alias },
  });

  if (!booking) {
    logger.warn('[SIP callback] Booking no encontrada para alias', { alias });
    throw new NotFoundError('Reserva no encontrada para el alias recibido');
  }

  // Pago de extensión — el alias es el bookingId y el qrId en el evento también es el bookingId
  if (booking.status === BookingStatus.IN_PROGRESS) {
    await confirmExtensionQrBySip(alias, alias);
    return { bookingId: alias, status: 'EXTENSION_CONFIRMED' };
  }

  if (booking.status !== BookingStatus.PENDING_PAYMENT) {
    // Race condition: QR expiró y nuestro job lo canceló (QR_ABANDONED) justo antes
    // de que el banco terminara de procesar un escaneo iniciado milisegundos antes.
    // Respondemos "0000" (éxito) para que SIP NO reintente el callback indefinidamente.
    // El pago queda en limbo — el admin debe revisarlo manualmente y decidir el reembolso.
    if (booking.cancellationSource === 'QR_ABANDONED') {
      logger.error('[SIP callback] ALERTA: pago recibido sobre reserva ya cancelada por expiración de QR — REVISIÓN MANUAL REQUERIDA', {
        bookingId: booking.id,
        alias,
        bookingStatus: booking.status,
        cancelledAt: booking.cancelledAt,
      });
      return { bookingId: booking.id, status: 'CANCELLED_QR_ABANDONED_RACE_CONDITION' };
    }

    // Idempotencia: si ya fue procesado correctamente, respondemos OK sin error
    if (booking.paidAt) {
      logger.info('[SIP callback] Pago ya procesado previamente', { bookingId: booking.id });
      return { bookingId: booking.id, status: booking.status };
    }

    throw new BadRequestError(`La reserva no está en estado esperado (estado: ${booking.status})`);
  }

  const updateResult = await prisma.booking.updateMany({
    where: { id: booking.id, status: BookingStatus.PENDING_PAYMENT },
    data: {
      status: BookingStatus.WAITING_CAREGIVER_APPROVAL,
      paidAt: new Date(),
    },
  });

  if (updateResult.count === 0) {
    logger.info('[SIP callback] Pago ya procesado por solicitud concurrente', { bookingId: booking.id });
    return { bookingId: booking.id, status: BookingStatus.WAITING_CAREGIVER_APPROVAL };
  }

  logger.info('[SIP callback] Pago confirmado — reserva esperando aprobación cuidador', { bookingId: booking.id, alias });
  track(booking.clientId, 'payment_completed', {
    bookingId: booking.id,
    method: 'sip_qr',
    amount: Number(booking.totalAmount),
  });

  notificationService.onBookingWaitingApproval(booking.id).catch((err) => {
    logger.error('[SIP callback] Notification failed', { bookingId: booking.id, err });
  });

  if (booking.donationAmount && Number(booking.donationAmount) > 0) {
    prisma.donation.upsert({
      where: { bookingId: booking.id },
      create: { bookingId: booking.id, clientId: booking.clientId, amount: booking.donationAmount },
      update: {},
    }).catch((err) => logger.error('[SIP callback] Donation record failed', { bookingId: booking.id, err }));
  }

  blockchainService.createBookingOnChain(
    booking.id,
    booking.clientId,
    booking.caregiverId,
    Number(booking.totalAmount),
    booking.startDate ?? booking.walkDate ?? new Date(),
    resolveBookingEndDate(booking),
    booking.petName,
    booking.serviceType
  ).then(async (txHash) => {
    if (txHash) {
      await prisma.booking.update({ where: { id: booking.id }, data: { blockchainTxHash: txHash } });
    }
  }).catch(err => {
    logger.error('[SIP callback] Blockchain registration failed', { bookingId: booking.id, err });
  });

  return { bookingId: booking.id, status: BookingStatus.WAITING_CAREGIVER_APPROVAL };
}
