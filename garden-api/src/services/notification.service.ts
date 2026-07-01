/**
 * Notification service: real Resend emails for all booking events.
 * WhatsApp remains a placeholder pending Twilio integration.
 */

import prisma from '../config/database.js';
import logger from '../shared/logger.js';
import { sendTransactionalEmail } from '../modules/auth/email.service.js';

// ---------------------------------------------------------------------------
// WhatsApp placeholder (Twilio integration TBD)
// ---------------------------------------------------------------------------

export function sendWhatsAppPlaceholder(
  toPhone: string,
  body: string,
  meta: { event: string; bookingId?: string }
): void {
  logger.info('[WHATSAPP_PLACEHOLDER]', { to: toPhone, event: meta.event, bookingId: meta.bookingId, bodyPreview: body.slice(0, 80) });
}

// ---------------------------------------------------------------------------
// Email template builder
// ---------------------------------------------------------------------------

function gardenEmail(title: string, bodyHtml: string): string {
  return `
    <div style="font-family:sans-serif;max-width:520px;margin:0 auto;background:#fff;border-radius:16px;overflow:hidden;box-shadow:0 2px 12px rgba(0,0,0,.08);">
      <div style="background:#16a34a;padding:28px 32px;text-align:center;">
        <h1 style="color:#fff;margin:0;font-size:24px;font-weight:900;letter-spacing:1px;">🌿 GARDEN</h1>
        <p style="color:#bbf7d0;margin:6px 0 0;font-size:13px;">Cuidadores de confianza</p>
      </div>
      <div style="padding:32px;">
        <h2 style="margin:0 0 16px;font-size:20px;color:#111;">${title}</h2>
        ${bodyHtml}
        <hr style="border:none;border-top:1px solid #e5e7eb;margin:24px 0;" />
        <p style="color:#9ca3af;font-size:12px;margin:0;text-align:center;">
          Este mensaje fue generado automáticamente por GARDEN. No respondas a este correo.
        </p>
      </div>
    </div>
  `;
}

function infoRow(label: string, value: string): string {
  return `<tr><td style="padding:6px 12px 6px 0;color:#6b7280;font-size:14px;white-space:nowrap;">${label}</td><td style="padding:6px 0;color:#111;font-size:14px;">${value}</td></tr>`;
}

function bookingTable(rows: Array<[string, string]>): string {
  return `<table style="width:100%;border-collapse:collapse;background:#f9fafb;border-radius:10px;padding:12px;margin:0 0 20px;" cellpadding="0" cellspacing="0"><tbody>${rows.map(([l, v]) => infoRow(l, v)).join('')}</tbody></table>`;
}

function ctaButton(text: string, url: string): string {
  return `<div style="text-align:center;margin:20px 0;"><a href="${url}" style="display:inline-block;background:#16a34a;color:#fff;text-decoration:none;font-weight:700;font-size:15px;padding:14px 32px;border-radius:10px;">${text}</a></div>`;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

async function getBookingWithContacts(bookingId: string) {
  return prisma.booking.findUnique({
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
}

function name(first?: string | null, last?: string | null, fallback = 'Usuario') {
  return [first, last].filter(Boolean).join(' ') || fallback;
}

function serviceLabel(type: string) {
  switch (type) {
    case 'HOSPEDAJE': return 'Hospedaje';
    case 'GUARDERIA': return 'Guardería';
    default: return 'Paseo';
  }
}

function dateRange(booking: { serviceType: string; startDate?: Date | null; endDate?: Date | null; walkDate?: Date | null; timeSlot?: string | null }): string {
  if (booking.serviceType === 'HOSPEDAJE' && booking.startDate && booking.endDate) {
    return `${booking.startDate.toISOString().slice(0, 10)} → ${booking.endDate.toISOString().slice(0, 10)}`;
  }
  if (booking.walkDate) {
    return booking.walkDate.toISOString().slice(0, 10) + (booking.timeSlot ? ` ${booking.timeSlot}` : '');
  }
  return 'Por confirmar';
}

function fireEmail(to: string, subject: string, html: string, event: string, bookingId?: string): void {
  sendTransactionalEmail(to, subject, html).catch((err: Error) => {
    logger.error(`[NOTIFICATION] Email failed to send`, { event, bookingId, to, error: err.message });
  });
}

// ---------------------------------------------------------------------------
// Booking events
// ---------------------------------------------------------------------------

/**
 * Payment confirmed → booking CONFIRMED. Notifies client and caregiver.
 */
export async function onBookingConfirmed(bookingId: string): Promise<void> {
  const booking = await getBookingWithContacts(bookingId);
  if (!booking) {
    logger.warn('[NOTIFICATION] onBookingConfirmed: booking not found', { bookingId });
    return;
  }

  const clientName = name(booking.client.firstName, booking.client.lastName, 'Cliente');
  const caregiverName = name(booking.caregiver?.user?.firstName, booking.caregiver?.user?.lastName, 'Cuidador');
  const svc = serviceLabel(booking.serviceType);
  const dates = dateRange(booking);

  // Email to client
  const clientHtml = gardenEmail(
    `¡Tu reserva de ${svc} está confirmada! 🎉`,
    `<p style="color:#555;font-size:14px;margin:0 0 20px;">Hola <strong>${clientName}</strong>, ¡todo listo! Tu reserva ha sido confirmada exitosamente.</p>` +
    bookingTable([
      ['Servicio', svc],
      ['Cuidador', caregiverName],
      ['Mascota', booking.petName],
      ['Fechas', dates],
      ['Total pagado', `Bs ${booking.totalAmount}`],
      ['ID de reserva', bookingId.slice(0, 8).toUpperCase()],
    ]) +
    `<p style="color:#555;font-size:14px;margin:0;">Si tienes alguna pregunta, puedes comunicarte directamente con tu cuidador a través del chat de la app. ¡Que disfruten el servicio! 🐾</p>`
  );
  fireEmail(booking.client.email, `Reserva confirmada – GARDEN`, clientHtml, 'BOOKING_CONFIRMED_CLIENT', bookingId);

  // Email to caregiver
  if (booking.caregiver?.user) {
    const caregiverHtml = gardenEmail(
      `Nueva reserva confirmada 🗓️`,
      `<p style="color:#555;font-size:14px;margin:0 0 20px;">Hola <strong>${caregiverName}</strong>, tienes una nueva reserva confirmada.</p>` +
      bookingTable([
        ['Servicio', svc],
        ['Cliente', clientName],
        ['Mascota', booking.petName],
        ['Fechas', dates],
        ['ID de reserva', bookingId.slice(0, 8).toUpperCase()],
      ]) +
      `<p style="color:#555;font-size:14px;margin:0;">Recuerda estar disponible en las fechas acordadas. Puedes hablar con el cliente a través del chat de la app. ¡Mucho éxito! 🌿</p>`
    );
    fireEmail(booking.caregiver.user.email, `Nueva reserva confirmada – GARDEN`, caregiverHtml, 'BOOKING_CONFIRMED_CAREGIVER', bookingId);

    sendWhatsAppPlaceholder(
      booking.caregiver.user.phone,
      `GARDEN: Nueva reserva confirmada. Cliente: ${clientName}. ${svc} - ${dates}. ID: ${bookingId}.`,
      { event: 'BOOKING_CONFIRMED_CAREGIVER', bookingId }
    );
  }

  sendWhatsAppPlaceholder(
    booking.client.phone,
    `GARDEN: Tu reserva de ${svc} está confirmada. Fechas: ${dates}. Reserva ${bookingId}.`,
    { event: 'BOOKING_CONFIRMED_CLIENT', bookingId }
  );
}

/**
 * Client cancelled the booking. Notifies caregiver.
 */
export async function onClientCancelled(bookingId: string): Promise<void> {
  const booking = await getBookingWithContacts(bookingId);
  if (!booking?.caregiver?.user) return;

  const caregiverName = name(booking.caregiver.user.firstName, booking.caregiver.user.lastName, 'Cuidador');
  const clientName = name(booking.client.firstName, booking.client.lastName, 'Cliente');
  const svc = serviceLabel(booking.serviceType);
  const dates = dateRange(booking);

  const html = gardenEmail(
    `Reserva cancelada por el cliente`,
    `<p style="color:#555;font-size:14px;margin:0 0 20px;">Hola <strong>${caregiverName}</strong>, te informamos que el cliente ha cancelado la reserva.</p>` +
    bookingTable([
      ['Cliente', clientName],
      ['Servicio', svc],
      ['Mascota', booking.petName],
      ['Fechas', dates],
      ['ID de reserva', bookingId.slice(0, 8).toUpperCase()],
    ]) +
    `<p style="color:#555;font-size:14px;margin:0;">Las fechas han quedado liberadas en tu agenda. Si tienes preguntas, contacta a nuestro soporte.</p>`
  );

  fireEmail(booking.caregiver.user.email, `Reserva cancelada por el cliente – GARDEN`, html, 'CLIENT_CANCELLED_CAREGIVER', bookingId);
  sendWhatsAppPlaceholder(booking.caregiver.user.phone, `GARDEN: El cliente canceló la reserva ${bookingId}.`, { event: 'CLIENT_CANCELLED_CAREGIVER', bookingId });
}

/**
 * Caregiver cancelled the booking. Notifies client with refund policy.
 */
export async function onCaregiverCancelled(bookingId: string, reason: string): Promise<void> {
  const booking = await getBookingWithContacts(bookingId);
  if (!booking) return;

  const clientName = name(booking.client.firstName, booking.client.lastName, 'Cliente');
  const caregiverName = name(booking.caregiver?.user?.firstName, booking.caregiver?.user?.lastName, 'El cuidador');
  const svc = serviceLabel(booking.serviceType);
  const dates = dateRange(booking);

  const html = gardenEmail(
    `Tu reserva fue cancelada`,
    `<p style="color:#555;font-size:14px;margin:0 0 20px;">Hola <strong>${clientName}</strong>, lamentamos informarte que ${caregiverName} tuvo que cancelar tu reserva.</p>` +
    bookingTable([
      ['Servicio', svc],
      ['Mascota', booking.petName],
      ['Fechas', dates],
      ['Motivo', reason || 'No especificado'],
      ['ID de reserva', bookingId.slice(0, 8).toUpperCase()],
    ]) +
    `<div style="background:#fef3c7;border:1px solid #fcd34d;border-radius:10px;padding:16px;margin:0 0 20px;">
       <p style="color:#92400e;font-size:14px;font-weight:700;margin:0 0 6px;">💰 Política de reembolso</p>
       <p style="color:#92400e;font-size:13px;margin:0;">Realizaremos la devolución total de tu dinero en un plazo máximo de 1 día hábil. Nuestro equipo de soporte se pondrá en contacto contigo a la brevedad.</p>
     </div>
     <p style="color:#555;font-size:14px;margin:0;">Sentimos los inconvenientes causados. Estamos aquí para ayudarte a encontrar un nuevo cuidador. 🌿</p>`
  );

  fireEmail(booking.client.email, `Tu reserva fue cancelada – GARDEN`, html, 'CAREGIVER_CANCELLED_CLIENT', bookingId);
  sendWhatsAppPlaceholder(
    booking.client.phone,
    `GARDEN: Tu reserva ${bookingId} fue cancelada por el cuidador. Motivo: ${reason}. Te contactaremos en 1 día hábil para tu devolución.`,
    { event: 'CAREGIVER_CANCELLED_CLIENT', bookingId }
  );
}

/**
 * Payment succeeded → booking WAITING_CAREGIVER_APPROVAL. Notifies caregiver.
 */
export async function onBookingWaitingApproval(bookingId: string): Promise<void> {
  const booking = await getBookingWithContacts(bookingId);
  if (!booking?.caregiver?.user) return;

  const caregiverName = name(booking.caregiver.user.firstName, booking.caregiver.user.lastName, 'Cuidador');
  const clientName = name(booking.client.firstName, booking.client.lastName, 'Cliente');
  const svc = serviceLabel(booking.serviceType);
  const dates = dateRange(booking);

  const html = gardenEmail(
    `Nueva solicitud de reserva — ¡Acción requerida! ⏰`,
    `<p style="color:#555;font-size:14px;margin:0 0 20px;">Hola <strong>${caregiverName}</strong>, tienes una nueva solicitud de reserva pagada esperando tu aprobación.</p>` +
    bookingTable([
      ['Servicio', svc],
      ['Cliente', clientName],
      ['Mascota', booking.petName],
      ['Fechas', dates],
      ['Total', `Bs ${booking.totalAmount}`],
      ['ID de reserva', bookingId.slice(0, 8).toUpperCase()],
    ]) +
    `<div style="background:#f0fdf4;border:1px solid #bbf7d0;border-radius:10px;padding:16px;margin:0 0 20px;">
       <p style="color:#166534;font-size:13px;margin:0;">⚠️ Tienes <strong>24 horas</strong> para aceptar o rechazar esta solicitud. Si no respondes, la reserva será cancelada automáticamente y el cliente recibirá un reembolso.</p>
     </div>
     <p style="color:#555;font-size:14px;margin:0;">Ingresa a la app para <strong>Aceptar</strong> o <strong>Rechazar</strong> esta solicitud.</p>`
  );

  fireEmail(booking.caregiver.user.email, `Nueva solicitud de reserva pendiente – GARDEN`, html, 'BOOKING_WAITING_APPROVAL', bookingId);
  sendWhatsAppPlaceholder(
    booking.caregiver.user.phone,
    `GARDEN: Nueva reserva de ${svc} pagada (${booking.petName}). ID: ${bookingId}. Por favor, ingresa al panel para Aceptar o Rechazar.`,
    { event: 'BOOKING_WAITING_APPROVAL', bookingId }
  );
}

/**
 * Caregiver accepted → booking CONFIRMED. Notifies client.
 */
export async function onBookingAccepted(bookingId: string): Promise<void> {
  const booking = await getBookingWithContacts(bookingId);
  if (!booking) return;

  const clientName = name(booking.client.firstName, booking.client.lastName, 'Cliente');
  const caregiverName = name(booking.caregiver?.user?.firstName, booking.caregiver?.user?.lastName, 'Tu cuidador');
  const svc = serviceLabel(booking.serviceType);
  const dates = dateRange(booking);

  const html = gardenEmail(
    `¡Tu reserva fue aceptada! 🎉`,
    `<p style="color:#555;font-size:14px;margin:0 0 20px;">Hola <strong>${clientName}</strong>, ¡buenas noticias! <strong>${caregiverName}</strong> ha aceptado tu reserva.</p>` +
    bookingTable([
      ['Servicio', svc],
      ['Cuidador', caregiverName],
      ['Mascota', booking.petName],
      ['Fechas', dates],
      ['Estado', 'CONFIRMADA ✅'],
      ['ID de reserva', bookingId.slice(0, 8).toUpperCase()],
    ]) +
    `<p style="color:#555;font-size:14px;margin:0;">Puedes comunicarte con tu cuidador a través del chat de la app. ¡Que disfruten el servicio! 🐾</p>`
  );

  fireEmail(booking.client.email, `¡Tu reserva fue aceptada! – GARDEN`, html, 'BOOKING_ACCEPTED_CLIENT', bookingId);
  sendWhatsAppPlaceholder(
    booking.client.phone,
    `GARDEN: ¡Tu reserva ${bookingId} ha sido aceptada por ${caregiverName}! Ya está CONFIRMADA.`,
    { event: 'BOOKING_ACCEPTED_CLIENT', bookingId }
  );
}

/**
 * Caregiver rejected → booking REJECTED_BY_CAREGIVER. Notifies client with refund info.
 */
export async function onBookingRejected(bookingId: string, reason: string): Promise<void> {
  const booking = await getBookingWithContacts(bookingId);
  if (!booking) return;

  const clientName = name(booking.client.firstName, booking.client.lastName, 'Cliente');
  const caregiverName = name(booking.caregiver?.user?.firstName, booking.caregiver?.user?.lastName, 'El cuidador');
  const svc = serviceLabel(booking.serviceType);
  const dates = dateRange(booking);

  const html = gardenEmail(
    `Actualización sobre tu reserva`,
    `<p style="color:#555;font-size:14px;margin:0 0 20px;">Hola <strong>${clientName}</strong>, lamentamos informarte que ${caregiverName} no puede atender tu reserva en esta ocasión.</p>` +
    bookingTable([
      ['Servicio', svc],
      ['Mascota', booking.petName],
      ['Fechas', dates],
      ['Motivo', reason || 'No especificado'],
      ['ID de reserva', bookingId.slice(0, 8).toUpperCase()],
    ]) +
    `<div style="background:#fef3c7;border:1px solid #fcd34d;border-radius:10px;padding:16px;margin:0 0 20px;">
       <p style="color:#92400e;font-size:14px;font-weight:700;margin:0 0 6px;">💰 Reembolso automático</p>
       <p style="color:#92400e;font-size:13px;margin:0;">Se realizará la <strong>devolución total</strong> de tu dinero en un plazo máximo de <strong>24 horas hábiles</strong>. Nuestro equipo de soporte se contactará contigo a la brevedad.</p>
     </div>
     <p style="color:#555;font-size:14px;margin:0;">Sentimos los inconvenientes. Puedes buscar otro cuidador disponible en la app. 🌿</p>`
  );

  fireEmail(booking.client.email, `Actualización sobre tu reserva – GARDEN`, html, 'BOOKING_REJECTED_CLIENT', bookingId);
  sendWhatsAppPlaceholder(
    booking.client.phone,
    `GARDEN: Tu reserva ${bookingId} no pudo ser aceptada por el cuidador. Motivo: ${reason}. Recibirás tu reembolso total en 24 horas hábiles.`,
    { event: 'BOOKING_REJECTED_CLIENT', bookingId }
  );
}

/**
 * Service started (IN_PROGRESS). Email to client.
 */
export async function onServiceStarted(bookingId: string): Promise<void> {
  const booking = await getBookingWithContacts(bookingId);
  if (!booking) return;

  const clientName = name(booking.client.firstName, booking.client.lastName, 'Cliente');
  const caregiverName = name(booking.caregiver?.user?.firstName, booking.caregiver?.user?.lastName, 'Tu cuidador');
  const svc = serviceLabel(booking.serviceType);

  const html = gardenEmail(
    `¡El servicio ha comenzado! 🐕`,
    `<p style="color:#555;font-size:14px;margin:0 0 20px;">Hola <strong>${clientName}</strong>, tu cuidador <strong>${caregiverName}</strong> acaba de iniciar el servicio.</p>` +
    bookingTable([
      ['Servicio', svc],
      ['Mascota', booking.petName],
      ['Inicio', new Date().toLocaleString('es-BO', { dateStyle: 'medium', timeStyle: 'short' })],
      ['ID de reserva', bookingId.slice(0, 8).toUpperCase()],
    ]) +
    `<p style="color:#555;font-size:14px;margin:0;">Puedes seguir el progreso en tiempo real desde la sección <strong>"Mis reservas"</strong> en la app. Si necesitas contactar a tu cuidador, hazlo a través del chat. 🐾</p>`
  );

  fireEmail(booking.client.email, `¡El servicio comenzó! – GARDEN`, html, 'SERVICE_STARTED_CLIENT', bookingId);
  sendWhatsAppPlaceholder(booking.client.phone, `GARDEN: ${caregiverName} inició el servicio para ${booking.petName}. Síguelo en la app.`, { event: 'SERVICE_STARTED_CLIENT', bookingId });
}

/**
 * Service completed (COMPLETED). Email to client with summary and review prompt.
 */
export async function onServiceCompleted(bookingId: string): Promise<void> {
  const booking = await getBookingWithContacts(bookingId);
  if (!booking) return;

  const clientName = name(booking.client.firstName, booking.client.lastName, 'Cliente');
  const caregiverName = name(booking.caregiver?.user?.firstName, booking.caregiver?.user?.lastName, 'Tu cuidador');
  const svc = serviceLabel(booking.serviceType);

  const html = gardenEmail(
    `Servicio finalizado ✅`,
    `<p style="color:#555;font-size:14px;margin:0 0 20px;">Hola <strong>${clientName}</strong>, el servicio de <strong>${svc}</strong> para <strong>${booking.petName}</strong> ha finalizado correctamente.</p>` +
    bookingTable([
      ['Servicio', svc],
      ['Cuidador', caregiverName],
      ['Mascota', booking.petName],
      ['Total pagado', `Bs ${booking.totalAmount}`],
      ['ID de reserva', bookingId.slice(0, 8).toUpperCase()],
    ]) +
    `<div style="background:#f0fdf4;border:1px solid #bbf7d0;border-radius:10px;padding:16px;margin:0 0 20px;">
       <p style="color:#166534;font-size:14px;font-weight:700;margin:0 0 6px;">⭐ ¡Deja tu reseña!</p>
       <p style="color:#166534;font-size:13px;margin:0;">Tu opinión ayuda a otros dueños a encontrar cuidadores confiables. Ingresa a la app y califica el servicio para liberar el pago al cuidador.</p>
     </div>
     <p style="color:#555;font-size:14px;margin:0;">Gracias por confiar en GARDEN. ¡Esperamos verte pronto! 🌿</p>`
  );

  fireEmail(booking.client.email, `Servicio finalizado – GARDEN`, html, 'SERVICE_COMPLETED_CLIENT', bookingId);
  sendWhatsAppPlaceholder(booking.client.phone, `GARDEN: El servicio de ${svc} para ${booking.petName} finalizó. Entra a la app para dejar tu reseña y liberar el pago.`, { event: 'SERVICE_COMPLETED_CLIENT', bookingId });
}

/**
 * Admin approved caregiver profile. Email to caregiver.
 */
export async function onCaregiverApproved(caregiverUserId: string): Promise<void> {
  try {
    const user = await prisma.user.findUnique({
      where: { id: caregiverUserId },
      select: { email: true, firstName: true, lastName: true },
    });
    if (!user?.email) return;

    const caregiverName = name(user.firstName, user.lastName, 'Cuidador');
    const html = gardenEmail(
      `¡Tu perfil fue aprobado! 🎉`,
      `<p style="color:#555;font-size:14px;margin:0 0 20px;">Hola <strong>${caregiverName}</strong>, ¡estamos felices de darte la bienvenida como cuidador verificado de GARDEN!</p>` +
      `<div style="background:#f0fdf4;border:1px solid #bbf7d0;border-radius:10px;padding:20px;margin:0 0 20px;text-align:center;">
         <p style="color:#166534;font-size:32px;margin:0 0 8px;">✅</p>
         <p style="color:#166534;font-size:16px;font-weight:700;margin:0 0 6px;">Perfil Aprobado</p>
         <p style="color:#166534;font-size:13px;margin:0;">Tu perfil ya es visible en el marketplace de GARDEN</p>
       </div>
       <p style="color:#555;font-size:14px;margin:0 0 16px;">A partir de ahora puedes:</p>
       <ul style="color:#555;font-size:14px;margin:0 0 20px;padding-left:20px;line-height:1.8;">
         <li>Recibir solicitudes de reserva de dueños de mascotas</li>
         <li>Configurar tu disponibilidad y tarifas</li>
         <li>Aceptar o rechazar reservas según tu agenda</li>
         <li>Ganar dinero haciendo lo que más te gusta</li>
       </ul>
       <p style="color:#555;font-size:14px;margin:0;">¡Mucho éxito y bienvenido a la familia GARDEN! 🌿🐾</p>`
    );

    fireEmail(user.email, `¡Tu perfil fue aprobado! – GARDEN`, html, 'CAREGIVER_APPROVED', caregiverUserId);
  } catch (err: any) {
    logger.error('[NOTIFICATION] onCaregiverApproved error', { caregiverUserId, error: err.message });
  }
}

/**
 * Admin rejected caregiver profile. Email to caregiver with reason.
 */
export async function onCaregiverRejected(caregiverUserId: string, reason: string, adminMessage?: string): Promise<void> {
  try {
    const user = await prisma.user.findUnique({
      where: { id: caregiverUserId },
      select: { email: true, firstName: true, lastName: true },
    });
    if (!user?.email) return;

    const caregiverName = name(user.firstName, user.lastName, 'Cuidador');
    const displayReason = adminMessage || reason || 'No se especificó un motivo.';

    const html = gardenEmail(
      `Actualización sobre tu solicitud de cuidador`,
      `<p style="color:#555;font-size:14px;margin:0 0 20px;">Hola <strong>${caregiverName}</strong>, hemos revisado tu solicitud para ser cuidador en GARDEN.</p>` +
      `<div style="background:#fef2f2;border:1px solid #fecaca;border-radius:10px;padding:16px;margin:0 0 20px;">
         <p style="color:#991b1b;font-size:14px;font-weight:700;margin:0 0 8px;">❌ Solicitud no aprobada</p>
         <p style="color:#991b1b;font-size:13px;margin:0;"><strong>Motivo:</strong> ${displayReason}</p>
       </div>
       <p style="color:#555;font-size:14px;margin:0 0 16px;">No te desanimes — puedes corregir los puntos indicados y enviar nuevamente tu solicitud desde la app.</p>
       <p style="color:#555;font-size:14px;margin:0;">Si tienes dudas sobre el proceso, escríbenos a través del chat de soporte en la app. Estamos aquí para ayudarte. 🌿</p>`
    );

    fireEmail(user.email, `Actualización sobre tu solicitud – GARDEN`, html, 'CAREGIVER_REJECTED', caregiverUserId);
  } catch (err: any) {
    logger.error('[NOTIFICATION] onCaregiverRejected error', { caregiverUserId, error: err.message });
  }
}

/**
 * Client rated the caregiver after service. Email summary to caregiver.
 */
export async function onRatingReceived(bookingId: string, rating: number, comment?: string): Promise<void> {
  const booking = await getBookingWithContacts(bookingId);
  if (!booking?.caregiver?.user) return;

  const caregiverName = name(booking.caregiver.user.firstName, booking.caregiver.user.lastName, 'Cuidador');
  const clientName = name(booking.client.firstName, booking.client.lastName, 'Cliente');
  const svc = serviceLabel(booking.serviceType);
  const stars = '⭐'.repeat(rating) + '☆'.repeat(5 - rating);

  const html = gardenEmail(
    `Nueva reseña de ${clientName} ${stars}`,
    `<p style="color:#555;font-size:14px;margin:0 0 20px;">Hola <strong>${caregiverName}</strong>, recibiste una reseña por tu servicio de <strong>${svc}</strong>.</p>` +
    bookingTable([
      ['Cliente', clientName],
      ['Servicio', svc],
      ['Mascota', booking.petName],
      ['Calificación', `${stars} (${rating}/5)`],
      ...(comment ? [['Comentario', comment] as [string, string]] : []),
      ['ID de reserva', bookingId.slice(0, 8).toUpperCase()],
    ]) +
    (rating >= 4
      ? `<div style="background:#f0fdf4;border:1px solid #bbf7d0;border-radius:10px;padding:16px;margin:0 0 20px;">
           <p style="color:#166534;font-size:13px;margin:0;">¡Excelente trabajo! Las reseñas positivas mejoran tu visibilidad en el marketplace. 🌟</p>
         </div>`
      : `<div style="background:#fef3c7;border:1px solid #fcd34d;border-radius:10px;padding:16px;margin:0 0 20px;">
           <p style="color:#92400e;font-size:13px;margin:0;">Cada reseña es una oportunidad de mejorar. Revisa los comentarios y sigue adelante. 💪</p>
         </div>`) +
    `<p style="color:#555;font-size:14px;margin:0;">Puedes ver todas tus reseñas en tu perfil dentro de la app. ¡Sigue así! 🌿</p>`
  );

  fireEmail(booking.caregiver.user.email, `Nueva reseña recibida – GARDEN`, html, 'RATING_RECEIVED_CAREGIVER', bookingId);
}

/**
 * Service reminder. Notifies client and caregiver X hours before service starts.
 * Call this from a cron job 24h and 2h before the scheduled service.
 */
export async function onServiceReminder(bookingId: string, hoursUntil: number): Promise<void> {
  const booking = await getBookingWithContacts(bookingId);
  if (!booking) return;

  const clientName = name(booking.client.firstName, booking.client.lastName, 'Cliente');
  const caregiverName = name(booking.caregiver?.user?.firstName, booking.caregiver?.user?.lastName, 'Tu cuidador');
  const svc = serviceLabel(booking.serviceType);
  const dates = dateRange(booking);
  const timeLabel = hoursUntil === 24 ? 'mañana' : `en ${hoursUntil} horas`;

  // Email to client
  const clientHtml = gardenEmail(
    `Recordatorio: tu servicio es ${timeLabel} ⏰`,
    `<p style="color:#555;font-size:14px;margin:0 0 20px;">Hola <strong>${clientName}</strong>, te recordamos que tienes un servicio programado <strong>${timeLabel}</strong>.</p>` +
    bookingTable([
      ['Servicio', svc],
      ['Cuidador', caregiverName],
      ['Mascota', booking.petName],
      ['Fecha', dates],
      ['ID de reserva', bookingId.slice(0, 8).toUpperCase()],
    ]) +
    `<p style="color:#555;font-size:14px;margin:0;">Asegúrate de coordinar la entrega de tu mascota con el cuidador a través del chat de la app. 🐾</p>`
  );
  fireEmail(booking.client.email, `Recordatorio de servicio – GARDEN`, clientHtml, 'SERVICE_REMINDER_CLIENT', bookingId);
  sendWhatsAppPlaceholder(booking.client.phone, `GARDEN: Recordatorio — tu servicio de ${svc} para ${booking.petName} es ${timeLabel}. ID: ${bookingId.slice(0, 8).toUpperCase()}.`, { event: 'SERVICE_REMINDER_CLIENT', bookingId });

  // Email to caregiver
  if (booking.caregiver?.user) {
    const caregiverHtml = gardenEmail(
      `Recordatorio: tienes un servicio ${timeLabel} ⏰`,
      `<p style="color:#555;font-size:14px;margin:0 0 20px;">Hola <strong>${caregiverName}</strong>, te recordamos que tienes un servicio programado <strong>${timeLabel}</strong>.</p>` +
      bookingTable([
        ['Servicio', svc],
        ['Cliente', clientName],
        ['Mascota', booking.petName],
        ['Fecha', dates],
        ['ID de reserva', bookingId.slice(0, 8).toUpperCase()],
      ]) +
      `<p style="color:#555;font-size:14px;margin:0;">Coordina la recepción de la mascota con el cliente a través del chat. ¡Mucho éxito! 🌿</p>`
    );
    fireEmail(booking.caregiver.user.email, `Recordatorio de servicio – GARDEN`, caregiverHtml, 'SERVICE_REMINDER_CAREGIVER', bookingId);
    sendWhatsAppPlaceholder(booking.caregiver.user.phone, `GARDEN: Recordatorio — tienes el servicio de ${svc} (${booking.petName}) ${timeLabel}. ID: ${bookingId.slice(0, 8).toUpperCase()}.`, { event: 'SERVICE_REMINDER_CAREGIVER', bookingId });
  }
}

/**
 * New caregiver approved — send welcome email + in-app notification.
 * Called right after auto-approval in caregiver-profile.service.ts.
 */
export async function onCaregiverWelcome(userId: string): Promise<void> {
  const user = await prisma.user.findUnique({
    where: { id: userId },
    select: { email: true, firstName: true, lastName: true },
  });
  if (!user) {
    logger.warn('[NOTIFICATION] onCaregiverWelcome: user not found', { userId });
    return;
  }

  const caregiverName = name(user.firstName, user.lastName, 'Cuidador');
  const guideUrl = 'https://gardenbo.com/guia-cuidador';

  const html = gardenEmail(
    `¡Bienvenido a GARDEN, ${caregiverName}! 🌿`,
    `<p style="color:#555;font-size:14px;margin:0 0 16px;">
      Hola <strong>${caregiverName}</strong>, ¡tu perfil ha sido aprobado y ya eres parte de la familia GARDEN! 🎉
    </p>
    <p style="color:#555;font-size:14px;margin:0 0 20px;">
      A partir de ahora puedes recibir solicitudes de reserva y empezar a ganar dinero haciendo lo que te apasiona: cuidar mascotas.
    </p>

    <div style="background:#f0fdf4;border:1px solid #bbf7d0;border-radius:12px;padding:20px;margin:0 0 20px;">
      <p style="color:#166534;font-weight:700;font-size:15px;margin:0 0 12px;">📋 Tus primeros pasos</p>
      <ol style="color:#166534;font-size:14px;margin:0;padding-left:20px;line-height:1.9;">
        <li>Activa tu <strong>disponibilidad</strong> en el calendario</li>
        <li>Revisa tus <strong>precios</strong> para cada servicio</li>
        <li>Completa o mejora tu <strong>bio y fotos</strong> para atraer más clientes</li>
        <li>Responde <strong>rápido</strong> a las solicitudes — aumenta tu ranking</li>
      </ol>
    </div>

    <div style="background:#f9fafb;border-radius:10px;padding:16px;margin:0 0 20px;">
      <p style="color:#374151;font-weight:700;font-size:14px;margin:0 0 10px;">💰 ¿Cómo funciona el pago?</p>
      <p style="color:#555;font-size:14px;margin:0;">
        Tú fijas tus precios. GARDEN retiene el <strong>10%</strong> por reserva completada.
        El <strong>90%</strong> restante entra automáticamente a tu billetera dentro de la app.
        Puedes retirar a tu banco o Tigo Money cuando quieras (mínimo Bs 50).
      </p>
    </div>

    <div style="background:#f9fafb;border-radius:10px;padding:16px;margin:0 0 24px;">
      <p style="color:#374151;font-weight:700;font-size:14px;margin:0 0 10px;">🆘 Soporte GARDEN</p>
      <p style="color:#555;font-size:14px;margin:0 0 4px;">
        📱 WhatsApp: <a href="https://wa.me/59178081291" style="color:#16a34a;text-decoration:none;">+591 78081291</a>
      </p>
      <p style="color:#555;font-size:14px;margin:0;">
        ✉️ Email: <a href="mailto:contactogardenbo@gmail.com" style="color:#16a34a;text-decoration:none;">contactogardenbo@gmail.com</a>
      </p>
    </div>

    <p style="color:#555;font-size:14px;margin:0 0 4px;text-align:center;">
      Hemos preparado una guía completa con todo lo que necesitas saber para empezar con el pie derecho. ¡No te la pierdas!
    </p>` +
    ctaButton('Ver guía del cuidador 🌿', guideUrl) +
    `<p style="color:#9ca3af;font-size:12px;margin:16px 0 0;text-align:center;">
      ¡Gracias por unirte a GARDEN! Cuidadores de confianza 🐾
    </p>`
  );

  fireEmail(user.email, '¡Bienvenido a GARDEN! Tu guía para empezar 🌿', html, 'CAREGIVER_WELCOME');

  // In-app notification
  await prisma.notification.create({
    data: {
      userId,
      title: '¡Bienvenido a GARDEN! 🌿',
      message: `¡Hola ${caregiverName}! Tu perfil está aprobado. Lee la guía completa para cuidadores para saber cómo recibir reservas, cobrar y aprovechar al máximo la plataforma.`,
      type: 'CAREGIVER_WELCOME',
    },
  });
}

/**
 * Refund processed / client info message.
 */
export async function onRefundProcessed(bookingId: string, message: string): Promise<void> {
  const booking = await getBookingWithContacts(bookingId);
  if (!booking) {
    logger.warn('[NOTIFICATION] onRefundProcessed: booking not found', { bookingId });
    return;
  }

  const clientName = name(booking.client.firstName, booking.client.lastName, 'Cliente');
  const svc = serviceLabel(booking.serviceType);

  const html = gardenEmail(
    `Información sobre tu reembolso 💰`,
    `<p style="color:#555;font-size:14px;margin:0 0 20px;">Hola <strong>${clientName}</strong>, aquí tienes una actualización sobre tu reembolso.</p>` +
    bookingTable([
      ['Servicio', svc],
      ['Mascota', booking.petName],
      ['ID de reserva', bookingId.slice(0, 8).toUpperCase()],
    ]) +
    `<div style="background:#f0fdf4;border:1px solid #bbf7d0;border-radius:10px;padding:16px;margin:0 0 20px;">
       <p style="color:#166534;font-size:14px;margin:0;">${message}</p>
     </div>
     <p style="color:#555;font-size:14px;margin:0;">El soporte de GARDEN se pondrá en contacto contigo para completar el proceso si aplica. Gracias por tu paciencia. 🌿</p>`
  );

  fireEmail(booking.client.email, `Información sobre tu reembolso – GARDEN`, html, 'REFUND_PROCESSED_CLIENT', bookingId);
  sendWhatsAppPlaceholder(
    booking.client.phone,
    `GARDEN: ${message} El soporte se pondrá en contacto.`,
    { event: 'REFUND_PROCESSED_CLIENT', bookingId }
  );
}
