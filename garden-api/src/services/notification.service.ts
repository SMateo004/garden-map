/**
 * Servicio de notificaciones: placeholders para Email y WhatsApp (Twilio).
 * Integración futura: sustituir sendEmailPlaceholder y sendWhatsAppPlaceholder
 * por llamadas a SendGrid/Resend (email) y Twilio (WhatsApp).
 *
 * Flujo trazable: todos los envíos se registran con logger y payload para auditoría.
 */

import prisma from '../config/database.js';
import logger from '../shared/logger.js';

// ---------------------------------------------------------------------------
// Placeholders: sustituir por integración real
// ---------------------------------------------------------------------------

/**
 * Placeholder email. Integración futura: SendGrid, Resend, SES.
 * @see https://www.twilio.com/sendgrid/email-api
 */
export function sendEmailPlaceholder(
  to: string,
  subject: string,
  body: string,
  meta: { event: string; bookingId?: string }
): void {
  logger.info('[NOTIFICATION] Email placeholder', {
    event: meta.event,
    bookingId: meta.bookingId,
    to,
    subject,
    bodyLength: body.length,
  });
  logger.info('[EMAIL_PLACEHOLDER]', { to, subject, event: meta.event, bookingId: meta.bookingId });
  // TODO: await sendgrid.send({ to, subject, html: body });
}

/**
 * Placeholder WhatsApp (Twilio). Integración futura: Twilio API.
 * @see https://www.twilio.com/docs/whatsapp
 */
export function sendWhatsAppPlaceholder(
  toPhone: string,
  body: string,
  meta: { event: string; bookingId?: string }
): void {
  logger.info('[NOTIFICATION] WhatsApp placeholder', {
    event: meta.event,
    bookingId: meta.bookingId,
    to: toPhone,
    bodyLength: body.length,
  });
  logger.info('[WHATSAPP_PLACEHOLDER]', { to: toPhone, event: meta.event, bookingId: meta.bookingId, bodyPreview: body.slice(0, 80) });
  // TODO: await twilioClient.messages.create({ from: WHATSAPP_FROM, to: `whatsapp:${toPhone}`, body });
}

// ---------------------------------------------------------------------------
// Helpers: cargar reserva con contactos
// ---------------------------------------------------------------------------

async function getBookingWithContacts(bookingId: string) {
  const booking = await prisma.booking.findUnique({
    where: { id: bookingId },
    include: {
      client: { select: { id: true, email: true, phone: true, firstName: true, lastName: true } },
      caregiver: {
        select: {
          id: true,
          user: { select: { id: true, email: true, phone: true, firstName: true, lastName: true } },
        },
      },
    },
  });
  return booking;
}

// ---------------------------------------------------------------------------
// Eventos del flujo de reserva
// ---------------------------------------------------------------------------

/**
 * Pago confirmado → reserva CONFIRMED. Notifica a cliente y cuidador.
 */
export async function onBookingConfirmed(bookingId: string): Promise<void> {
  const booking = await getBookingWithContacts(bookingId);
  if (!booking) {
    logger.warn('[NOTIFICATION] onBookingConfirmed: booking not found', { bookingId });
    return;
  }

  const clientName = [booking.client.firstName, booking.client.lastName].filter(Boolean).join(' ') || 'Cliente';
  const caregiverName =
    booking.caregiver?.user != null
      ? [booking.caregiver.user.firstName, booking.caregiver.user.lastName].filter(Boolean).join(' ') || 'Cuidador'
      : 'Cuidador';
  const serviceLabel = booking.serviceType === 'HOSPEDAJE' ? 'Hospedaje' : 'Paseo';
  const dates =
    booking.serviceType === 'HOSPEDAJE' && booking.startDate && booking.endDate
      ? `${booking.startDate.toISOString().slice(0, 10)} - ${booking.endDate.toISOString().slice(0, 10)}`
      : booking.walkDate
        ? booking.walkDate.toISOString().slice(0, 10) + (booking.timeSlot ? ` ${booking.timeSlot}` : '')
        : '';

  const clientEmailSubject = `Reserva confirmada - GARDEN`;
  const clientEmailBody = `Hola ${clientName},\n\nTu reserva de ${serviceLabel} ha sido confirmada.\nReserva ID: ${bookingId}\nFechas: ${dates}\nMascota: ${booking.petName}\nMonto: Bs ${booking.totalAmount}.\n\nGracias por confiar en GARDEN.`;
  const clientWhatsAppBody = `GARDEN: Tu reserva de ${serviceLabel} está confirmada. Fechas: ${dates}. Reserva ${bookingId}.`;

  sendEmailPlaceholder(
    booking.client.email,
    clientEmailSubject,
    clientEmailBody,
    { event: 'BOOKING_CONFIRMED_CLIENT', bookingId }
  );
  sendWhatsAppPlaceholder(booking.client.phone, clientWhatsAppBody, {
    event: 'BOOKING_CONFIRMED_CLIENT',
    bookingId,
  });

  if (booking.caregiver?.user) {
    const caregiverSubject = `Nueva reserva confirmada - GARDEN`;
    const caregiverBody = `Hola ${caregiverName},\n\nTienes una nueva reserva confirmada.\nReserva ID: ${bookingId}\nCliente: ${clientName}\nServicio: ${serviceLabel}\nFechas: ${dates}\nMascota: ${booking.petName}.`;
    const caregiverWhatsAppBody = `GARDEN: Nueva reserva confirmada. Cliente: ${clientName}. ${serviceLabel} - ${dates}. ID: ${bookingId}.`;

    sendEmailPlaceholder(booking.caregiver.user.email, caregiverSubject, caregiverBody, {
      event: 'BOOKING_CONFIRMED_CAREGIVER',
      bookingId,
    });
    sendWhatsAppPlaceholder(booking.caregiver.user.phone, caregiverWhatsAppBody, {
      event: 'BOOKING_CONFIRMED_CAREGIVER',
      bookingId,
    });
  }
}


/**
 * Cliente canceló la reserva. Notifica al cuidador.
 */
export async function onClientCancelled(bookingId: string): Promise<void> {
  const booking = await getBookingWithContacts(bookingId);
  if (!booking?.caregiver?.user) return;

  const caregiverName = [booking.caregiver.user.firstName, booking.caregiver.user.lastName]
    .filter(Boolean)
    .join(' ') || 'Cuidador';
  const clientName = [booking.client.firstName, booking.client.lastName].filter(Boolean).join(' ') || 'Cliente';
  const subject = `Reserva cancelada por el cliente - GARDEN`;
  const body = `Hola ${caregiverName},\n\nEl cliente ${clientName} ha cancelado la reserva ${bookingId}.`;
  sendEmailPlaceholder(booking.caregiver.user.email, subject, body, {
    event: 'CLIENT_CANCELLED_CAREGIVER',
    bookingId,
  });
  sendWhatsAppPlaceholder(
    booking.caregiver.user.phone,
    `GARDEN: El cliente canceló la reserva ${bookingId}.`,
    { event: 'CLIENT_CANCELLED_CAREGIVER', bookingId }
  );
}

/**
 * Cuidador canceló la reserva. Notifica al cliente (dueño).
 */
export async function onCaregiverCancelled(bookingId: string, reason: string): Promise<void> {
  const booking = await getBookingWithContacts(bookingId);
  if (!booking) return;

  const clientName = [booking.client.firstName, booking.client.lastName].filter(Boolean).join(' ') || 'Cliente';
  const caregiverName = booking.caregiver?.user
    ? [booking.caregiver.user.firstName, booking.caregiver.user.lastName].filter(Boolean).join(' ')
    : 'El cuidador';

  const subject = `Reserva cancelada por el cuidador - GARDEN`;
  const body = `Hola ${clientName},\n\nLamentamos informarte que ${caregiverName} ha cancelado la reserva ${bookingId}.\n\nMotivo: ${reason}\n\nPOLÍTICA DE REEMBOLSO:\nNuestra empresa se pondrá en contacto contigo en un plazo de 1 día hábil para realizar la devolución correspondiente.\n\nSentimos los inconvenientes causados.`;

  sendEmailPlaceholder(booking.client.email, subject, body, {
    event: 'CAREGIVER_CANCELLED_CLIENT',
    bookingId,
  });

  sendWhatsAppPlaceholder(
    booking.client.phone,
    `GARDEN: Tu reserva ${bookingId} fue cancelada por el cuidador. Motivo: ${reason}. Te contactaremos en 1 día hábil para tu devolución.`,
    { event: 'CAREGIVER_CANCELLED_CLIENT', bookingId }
  );
}

/**
 * Pago exitoso -> Reserva en WAITING_CAREGIVER_APPROVAL. Notifica al cuidador.
 */
export async function onBookingWaitingApproval(bookingId: string): Promise<void> {
  const booking = await getBookingWithContacts(bookingId);
  if (!booking?.caregiver?.user) return;

  const caregiverName = [booking.caregiver.user.firstName, booking.caregiver.user.lastName].filter(Boolean).join(' ') || 'Cuidador';
  const serviceLabel = booking.serviceType === 'HOSPEDAJE' ? 'Hospedaje' : 'Paseo';

  const subject = `Nueva solicitud de reserva pagada - GARDEN`;
  const body = `Hola ${caregiverName},\n\nTienes una nueva solicitud de ${serviceLabel} pagada y esperando tu aprobación.\nReserva ID: ${bookingId}\nMascota: ${booking.petName}.\n\nPor favor, ingresa al panel para Aceptar o Rechazar la solicitud.`;
  const whatsappBody = `GARDEN: Nueva reserva de ${serviceLabel} pagada (${booking.petName}). ID: ${bookingId}. Por favor, ingresa al panel para Aceptar o Rechazar.`;

  sendEmailPlaceholder(booking.caregiver.user.email, subject, body, { event: 'BOOKING_WAITING_APPROVAL', bookingId });
  sendWhatsAppPlaceholder(booking.caregiver.user.phone, whatsappBody, { event: 'BOOKING_WAITING_APPROVAL', bookingId });
}

/**
 * Cuidador aceptó -> Reserva CONFIRMED. Notifica al cliente.
 */
export async function onBookingAccepted(bookingId: string): Promise<void> {
  const booking = await getBookingWithContacts(bookingId);
  if (!booking) return;

  const clientName = [booking.client.firstName, booking.client.lastName].filter(Boolean).join(' ') || 'Cliente';
  const caregiverName = booking.caregiver?.user ? [booking.caregiver.user.firstName, booking.caregiver.user.lastName].filter(Boolean).join(' ') : 'El cuidador';

  const subject = `¡Tu reserva ha sido aceptada! - GARDEN`;
  const body = `Hola ${clientName},\n\n¡Buenas noticias! ${caregiverName} ha aceptado tu reserva ${bookingId}.\n\nTu reserva ahora está CONFIRMADA. ¡Disfruta del servicio!`;
  const whatsappBody = `GARDEN: ¡Tu reserva ${bookingId} ha sido aceptada por ${caregiverName}! Ya está CONFIRMADA.`;

  sendEmailPlaceholder(booking.client.email, subject, body, { event: 'BOOKING_ACCEPTED_CLIENT', bookingId });
  sendWhatsAppPlaceholder(booking.client.phone, whatsappBody, { event: 'BOOKING_ACCEPTED_CLIENT', bookingId });
}

/**
 * Cuidador rechazó -> Reserva REJECTED_BY_CAREGIVER. Notifica al cliente sobre el reembolso.
 */
export async function onBookingRejected(bookingId: string, reason: string): Promise<void> {
  const booking = await getBookingWithContacts(bookingId);
  if (!booking) return;

  const clientName = [booking.client.firstName, booking.client.lastName].filter(Boolean).join(' ') || 'Cliente';
  const caregiverName = booking.caregiver?.user ? [booking.caregiver.user.firstName, booking.caregiver.user.lastName].filter(Boolean).join(' ') : 'El cuidador';

  const subject = `Actualización sobre tu reserva - GARDEN`;
  const body = `Hola ${clientName},\n\nLamentamos informarte que ${caregiverName} no puede atender tu reserva ${bookingId} en esta ocasión.\n\nMotivo: ${reason}\n\nPOLÍTICA DE REEMBOLSO:\nSe realizará la devolución total de tu dinero en un plazo de 1 día hábil (24 horas). Nuestro equipo de soporte se contactará contigo a la brevedad.`;
  const whatsappBody = `GARDEN: Tu reserva ${bookingId} no pudo ser aceptada por el cuidador. Motivo: ${reason}. Recibirás tu reembolso total en 24 horas hábiles.`;

  sendEmailPlaceholder(booking.client.email, subject, body, { event: 'BOOKING_REJECTED_CLIENT', bookingId });
  sendWhatsAppPlaceholder(booking.client.phone, whatsappBody, { event: 'BOOKING_REJECTED_CLIENT', bookingId });
}

/**
 * Reembolso procesado / información al cliente. Mensaje: "El soporte se pondrá en contacto".
 */
export async function onRefundProcessed(bookingId: string, message: string): Promise<void> {
  const booking = await getBookingWithContacts(bookingId);
  if (!booking) {
    logger.warn('[NOTIFICATION] onRefundProcessed: booking not found', { bookingId });
    return;
  }

  const clientName = [booking.client.firstName, booking.client.lastName].filter(Boolean).join(' ') || 'Cliente';
  const subject = `Reembolso - GARDEN`;
  const body = `Hola ${clientName},\n\nReserva ${bookingId} cancelada.\n\n${message}\n\nEl soporte se pondrá en contacto para completar el proceso si aplica.`;
  sendEmailPlaceholder(booking.client.email, subject, body, {
    event: 'REFUND_PROCESSED_CLIENT',
    bookingId,
  });
  const whatsAppBody = `GARDEN: ${message} El soporte se pondrá en contacto.`;
  sendWhatsAppPlaceholder(booking.client.phone, whatsAppBody, {
    event: 'REFUND_PROCESSED_CLIENT',
    bookingId,
  });
}
