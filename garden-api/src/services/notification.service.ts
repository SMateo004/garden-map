/**
 * Notification service: real Resend emails for all booking events.
 * WhatsApp remains a placeholder for booking-event messages — the real
 * WhatsApp Business Cloud API integration lives in otp-delivery.service.ts
 * (used today for phone OTP only).
 */

import prisma from '../config/database.js';
import logger from '../shared/logger.js';
import { sendTransactionalEmail } from '../modules/auth/email.service.js';
import { sendPushToUser } from './firebase.service.js';

// ---------------------------------------------------------------------------
// WhatsApp placeholder (booking-event notifications — not yet wired to a
// real send; see otp-delivery.service.ts for the real WhatsApp integration)
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
    `Pago recibido: ${svc} de ${booking.petName} el ${dates} 🎉`,
    `<p style="color:#555;font-size:14px;margin:0 0 20px;">Hola <strong>${clientName}</strong>, tu pago de <strong>Bs ${booking.totalAmount}</strong> ya quedó registrado y <strong>${caregiverName}</strong> tiene la reserva de <strong>${booking.petName}</strong> anotada en su agenda.</p>` +
    bookingTable([
      ['Servicio', svc],
      ['Cuidador', caregiverName],
      ['Mascota', booking.petName],
      ['Fechas', dates],
      ['Total pagado', `Bs ${booking.totalAmount}`],
      ['ID de reserva', bookingId.slice(0, 8).toUpperCase()],
    ]) +
    `<p style="color:#555;font-size:14px;margin:0;">Cualquier detalle de último momento sobre ${booking.petName}, coordínalo directo con ${caregiverName} por el chat de la app. ¡Buen servicio! 🐾</p>`
  );
  fireEmail(booking.client.email, `Pago recibido — ${svc} de ${booking.petName} el ${dates}`, clientHtml, 'BOOKING_CONFIRMED_CLIENT', bookingId);

  // Email to caregiver
  if (booking.caregiver?.user) {
    const caregiverHtml = gardenEmail(
      `${clientName} ya pagó: ${svc} para ${booking.petName} 🗓️`,
      `<p style="color:#555;font-size:14px;margin:0 0 20px;">Hola <strong>${caregiverName}</strong>, el pago de <strong>${clientName}</strong> se acreditó y la reserva de <strong>${booking.petName}</strong> quedó agendada para el <strong>${dates}</strong>.</p>` +
      bookingTable([
        ['Servicio', svc],
        ['Cliente', clientName],
        ['Mascota', booking.petName],
        ['Fechas', dates],
        ['ID de reserva', bookingId.slice(0, 8).toUpperCase()],
      ]) +
      `<p style="color:#555;font-size:14px;margin:0;">Márcate esa fecha y coordina con ${clientName} la entrega de ${booking.petName} por el chat de la app. ¡Mucho éxito! 🌿</p>`
    );
    fireEmail(booking.caregiver.user.email, `Reserva agendada — ${svc} para ${booking.petName}`, caregiverHtml, 'BOOKING_CONFIRMED_CAREGIVER', bookingId);

    sendWhatsAppPlaceholder(
      booking.caregiver.user.phone,
      `GARDEN: ${clientName} pagó y agendó ${svc} para ${booking.petName} el ${dates}. ID: ${bookingId}.`,
      { event: 'BOOKING_CONFIRMED_CAREGIVER', bookingId }
    );
  }

  sendWhatsAppPlaceholder(
    booking.client.phone,
    `GARDEN: Listo, ${svc} de ${booking.petName} quedó agendado con ${caregiverName} para el ${dates}. Reserva ${bookingId}.`,
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
    `Se liberó tu agenda del ${dates}`,
    `<p style="color:#555;font-size:14px;margin:0 0 20px;">Hola <strong>${caregiverName}</strong>, <strong>${clientName}</strong> canceló la reserva de <strong>${svc}</strong> para <strong>${booking.petName}</strong> que tenías anotada el <strong>${dates}</strong>.</p>` +
    bookingTable([
      ['Cliente', clientName],
      ['Servicio', svc],
      ['Mascota', booking.petName],
      ['Fechas', dates],
      ['ID de reserva', bookingId.slice(0, 8).toUpperCase()],
    ]) +
    `<p style="color:#555;font-size:14px;margin:0;">Ese espacio ya está libre en tu calendario para otra reserva. Si tienes dudas, escríbenos a soporte.</p>`
  );

  fireEmail(booking.caregiver.user.email, `Se liberó tu agenda del ${dates} – GARDEN`, html, 'CLIENT_CANCELLED_CAREGIVER', bookingId);
  sendWhatsAppPlaceholder(booking.caregiver.user.phone, `GARDEN: ${clientName} canceló ${svc} de ${booking.petName} del ${dates}. Reserva ${bookingId}.`, { event: 'CLIENT_CANCELLED_CAREGIVER', bookingId });
  sendPushToUser(
    booking.caregiver.user.id,
    `Se canceló una reserva`,
    `${clientName} canceló ${svc} de ${booking.petName}. Ya puedes agendar otra reserva el ${dates}.`,
    { type: 'BOOKING_CANCELLED', bookingId }
  ).catch((err) => logger.warn('[NOTIFICATION] push onClientCancelled failed', { bookingId, err }));
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
    `${caregiverName} no podrá atender a ${booking.petName} el ${dates}`,
    `<p style="color:#555;font-size:14px;margin:0 0 20px;">Hola <strong>${clientName}</strong>, ${caregiverName} tuvo que cancelar la reserva de <strong>${svc}</strong> que tenías para <strong>${booking.petName}</strong> el <strong>${dates}</strong>.</p>` +
    bookingTable([
      ['Servicio', svc],
      ['Mascota', booking.petName],
      ['Fechas', dates],
      ['Motivo', reason || 'No especificado'],
      ['ID de reserva', bookingId.slice(0, 8).toUpperCase()],
    ]) +
    `<div style="background:#fef3c7;border:1px solid #fcd34d;border-radius:10px;padding:16px;margin:0 0 20px;">
       <p style="color:#92400e;font-size:14px;font-weight:700;margin:0 0 6px;">💰 Te devolvemos tus Bs ${booking.totalAmount}</p>
       <p style="color:#92400e;font-size:13px;margin:0;">El reembolso completo llega en un plazo máximo de 1 día hábil. Nuestro equipo de soporte se pondrá en contacto contigo a la brevedad.</p>
     </div>
     <p style="color:#555;font-size:14px;margin:0;">Ya puedes buscar otro cuidador disponible para ${booking.petName} el ${dates} directo desde la app. 🌿</p>`
  );

  fireEmail(booking.client.email, `${caregiverName} canceló tu reserva del ${dates} – GARDEN`, html, 'CAREGIVER_CANCELLED_CLIENT', bookingId);
  sendWhatsAppPlaceholder(
    booking.client.phone,
    `GARDEN: ${caregiverName} canceló ${svc} de ${booking.petName} del ${dates}. Te devolvemos tus Bs ${booking.totalAmount} en 1 día hábil.`,
    { event: 'CAREGIVER_CANCELLED_CLIENT', bookingId }
  );
  sendPushToUser(
    booking.client.id,
    `${caregiverName} canceló tu reserva`,
    `${booking.petName} se quedó sin cuidador el ${dates}. Te devolvemos tus Bs ${booking.totalAmount} en máx. 1 día hábil.`,
    { type: 'BOOKING_CANCELLED', bookingId }
  ).catch((err) => logger.warn('[NOTIFICATION] push onCaregiverCancelled failed', { bookingId, err }));
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
    `${clientName} quiere reservarte para ${booking.petName} — respondé antes de 24h ⏰`,
    `<p style="color:#555;font-size:14px;margin:0 0 20px;">Hola <strong>${caregiverName}</strong>, <strong>${clientName}</strong> ya pagó por <strong>${svc}</strong> para <strong>${booking.petName}</strong> y está esperando que aceptes.</p>` +
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

  fireEmail(booking.caregiver.user.email, `${clientName} espera tu respuesta — ${svc} de ${booking.petName}`, html, 'BOOKING_WAITING_APPROVAL', bookingId);
  sendWhatsAppPlaceholder(
    booking.caregiver.user.phone,
    `GARDEN: ${clientName} pagó ${svc} para ${booking.petName} (${dates}). ID: ${bookingId}. Ingresa al panel para Aceptar o Rechazar antes de 24h.`,
    { event: 'BOOKING_WAITING_APPROVAL', bookingId }
  );
  // Push — antes esta era la notificación que el dueño del negocio reportó
  // como "reserva confirmada, esperando tu aprobación... no me lleva a
  // ningún lado": el evento solo mandaba email/WhatsApp, nunca push, así
  // que el caregiver no se enteraba hasta revisar el correo. Con `data` acá,
  // FcmService._handleNotificationTap (Flutter) navega directo a la pantalla
  // de "Mis Reservas" del cuidador, donde está el botón Aceptar/Rechazar.
  sendPushToUser(
    booking.caregiver.user.id,
    `⏰ ${clientName} te espera`,
    `${booking.petName} necesita ${svc} el ${dates}. Tienes 24h para aceptar o rechazar.`,
    { type: 'BOOKING_WAITING_APPROVAL', bookingId }
  ).catch((err) => logger.warn('[NOTIFICATION] push onBookingWaitingApproval failed', { bookingId, err }));
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
    `${caregiverName} dijo que sí 🎉`,
    `<p style="color:#555;font-size:14px;margin:0 0 20px;">Hola <strong>${clientName}</strong>, <strong>${caregiverName}</strong> acaba de aceptar cuidar a <strong>${booking.petName}</strong> el <strong>${dates}</strong>.</p>` +
    bookingTable([
      ['Servicio', svc],
      ['Cuidador', caregiverName],
      ['Mascota', booking.petName],
      ['Fechas', dates],
      ['Estado', 'CONFIRMADA ✅'],
      ['ID de reserva', bookingId.slice(0, 8).toUpperCase()],
    ]) +
    `<p style="color:#555;font-size:14px;margin:0;">Coordina con ${caregiverName} los detalles de entrega de ${booking.petName} por el chat de la app. 🐾</p>`
  );

  fireEmail(booking.client.email, `${caregiverName} aceptó — ${svc} de ${booking.petName} confirmado`, html, 'BOOKING_ACCEPTED_CLIENT', bookingId);
  sendWhatsAppPlaceholder(
    booking.client.phone,
    `GARDEN: ${caregiverName} aceptó cuidar a ${booking.petName} el ${dates}. Tu reserva ${bookingId} ya está CONFIRMADA.`,
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
    `${caregiverName} no podrá atender a ${booking.petName} esta vez`,
    `<p style="color:#555;font-size:14px;margin:0 0 20px;">Hola <strong>${clientName}</strong>, ${caregiverName} no podrá tomar la reserva de <strong>${svc}</strong> que pediste para <strong>${booking.petName}</strong> el <strong>${dates}</strong>.</p>` +
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
     <p style="color:#555;font-size:14px;margin:0;">Aún puedes conseguir a alguien para ${booking.petName} el ${dates} — entra a la app y busca otro cuidador disponible esa fecha. 🌿</p>`
  );

  fireEmail(booking.client.email, `${caregiverName} no podrá atender esta reserva – GARDEN`, html, 'BOOKING_REJECTED_CLIENT', bookingId);
  sendWhatsAppPlaceholder(
    booking.client.phone,
    `GARDEN: ${caregiverName} no pudo tomar ${svc} de ${booking.petName} del ${dates}. Motivo: ${reason}. Reembolso total en 24h hábiles.`,
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

  const startedAt = new Date().toLocaleString('es-BO', { dateStyle: 'medium', timeStyle: 'short' });
  const html = gardenEmail(
    `${caregiverName} ya está con ${booking.petName} 🐕`,
    `<p style="color:#555;font-size:14px;margin:0 0 20px;">Hola <strong>${clientName}</strong>, <strong>${caregiverName}</strong> acaba de arrancar el ${svc.toLowerCase()} de <strong>${booking.petName}</strong>, a las <strong>${startedAt}</strong>.</p>` +
    bookingTable([
      ['Servicio', svc],
      ['Mascota', booking.petName],
      ['Inicio', startedAt],
      ['ID de reserva', bookingId.slice(0, 8).toUpperCase()],
    ]) +
    `<p style="color:#555;font-size:14px;margin:0;">Sigue el avance en tiempo real desde <strong>"Mis reservas"</strong> en la app. Cualquier cosa sobre ${booking.petName}, escríbele a ${caregiverName} por el chat. 🐾</p>`
  );

  fireEmail(booking.client.email, `${caregiverName} ya empezó con ${booking.petName} – GARDEN`, html, 'SERVICE_STARTED_CLIENT', bookingId);
  sendWhatsAppPlaceholder(booking.client.phone, `GARDEN: ${caregiverName} arrancó el ${svc.toLowerCase()} de ${booking.petName} a las ${startedAt}. Síguelo en la app.`, { event: 'SERVICE_STARTED_CLIENT', bookingId });
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
    `${booking.petName} ya está de vuelta contigo ✅`,
    `<p style="color:#555;font-size:14px;margin:0 0 20px;">Hola <strong>${clientName}</strong>, ${caregiverName} terminó el ${svc.toLowerCase()} de <strong>${booking.petName}</strong> sin novedades.</p>` +
    bookingTable([
      ['Servicio', svc],
      ['Cuidador', caregiverName],
      ['Mascota', booking.petName],
      ['Total pagado', `Bs ${booking.totalAmount}`],
      ['ID de reserva', bookingId.slice(0, 8).toUpperCase()],
    ]) +
    `<div style="background:#f0fdf4;border:1px solid #bbf7d0;border-radius:10px;padding:16px;margin:0 0 20px;">
       <p style="color:#166534;font-size:14px;font-weight:700;margin:0 0 6px;">⭐ Califica a ${caregiverName}</p>
       <p style="color:#166534;font-size:13px;margin:0;">Contá cómo le fue a ${booking.petName}. Tu reseña libera el pago de Bs ${booking.totalAmount} para ${caregiverName} y guía a otros dueños en Santa Cruz.</p>
     </div>
     <p style="color:#555;font-size:14px;margin:0;">Gracias por confiar en GARDEN para cuidar a ${booking.petName}. ¡Hasta la próxima! 🌿</p>`
  );

  fireEmail(booking.client.email, `${booking.petName} ya volvió — califica a ${caregiverName}`, html, 'SERVICE_COMPLETED_CLIENT', bookingId);
  sendWhatsAppPlaceholder(booking.client.phone, `GARDEN: ${caregiverName} terminó el ${svc.toLowerCase()} de ${booking.petName}. Entra a la app y califica para liberar el pago.`, { event: 'SERVICE_COMPLETED_CLIENT', bookingId });
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
      `Listo, ${caregiverName}: tu perfil ya es visible 🎉`,
      `<p style="color:#555;font-size:14px;margin:0 0 20px;">Hola <strong>${caregiverName}</strong>, revisamos tu perfil y quedó aprobado — ya apareces en las búsquedas de dueños de mascotas en Santa Cruz.</p>` +
      `<div style="background:#f0fdf4;border:1px solid #bbf7d0;border-radius:10px;padding:20px;margin:0 0 20px;text-align:center;">
         <p style="color:#166534;font-size:32px;margin:0 0 8px;">✅</p>
         <p style="color:#166534;font-size:16px;font-weight:700;margin:0 0 6px;">Perfil Aprobado</p>
         <p style="color:#166534;font-size:13px;margin:0;">Tu perfil ya es visible en el marketplace de GARDEN</p>
       </div>
       <p style="color:#555;font-size:14px;margin:0 0 16px;">Antes de tu primera reserva, dale un vistazo a esto:</p>
       <ul style="color:#555;font-size:14px;margin:0 0 20px;padding-left:20px;line-height:1.8;">
         <li>Activa tu disponibilidad para que te empiecen a llegar solicitudes</li>
         <li>Revisa las tarifas que fijaste para paseo, guardería y hospedaje</li>
         <li>Responde rápido cuando llegue una solicitud — eso mejora tu ranking</li>
       </ul>
       <p style="color:#555;font-size:14px;margin:0;">Mucho éxito con tus primeras reservas, ${caregiverName}. 🌿🐾</p>`
    );

    fireEmail(user.email, `${caregiverName}, tu perfil ya está aprobado – GARDEN`, html, 'CAREGIVER_APPROVED', caregiverUserId);
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
      `Tu solicitud de cuidador necesita ajustes`,
      `<p style="color:#555;font-size:14px;margin:0 0 20px;">Hola <strong>${caregiverName}</strong>, revisamos tu solicitud para ser cuidador en GARDEN y todavía no la podemos aprobar.</p>` +
      `<div style="background:#fef2f2;border:1px solid #fecaca;border-radius:10px;padding:16px;margin:0 0 20px;">
         <p style="color:#991b1b;font-size:14px;font-weight:700;margin:0 0 8px;">❌ Solicitud no aprobada</p>
         <p style="color:#991b1b;font-size:13px;margin:0;"><strong>Motivo:</strong> ${displayReason}</p>
       </div>
       <p style="color:#555;font-size:14px;margin:0 0 16px;">Corrige ese punto puntual y vuelve a enviar tu solicitud desde la app — la revisamos de nuevo apenas llegue.</p>
       <p style="color:#555;font-size:14px;margin:0;">Si algo no te queda claro, escríbenos por el chat de soporte en la app. 🌿</p>`
    );

    fireEmail(user.email, `${caregiverName}, tu solicitud necesita un ajuste – GARDEN`, html, 'CAREGIVER_REJECTED', caregiverUserId);
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
    `${clientName} te calificó con ${rating}/5 ${stars}`,
    `<p style="color:#555;font-size:14px;margin:0 0 20px;">Hola <strong>${caregiverName}</strong>, <strong>${clientName}</strong> te dejó una reseña por el <strong>${svc.toLowerCase()}</strong> de <strong>${booking.petName}</strong>.</p>` +
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

  fireEmail(booking.caregiver.user.email, `${clientName} te calificó ${rating}/5 – GARDEN`, html, 'RATING_RECEIVED_CAREGIVER', bookingId);
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
  const timeLabel = hoursUntil === 24
    ? 'mañana'
    : hoursUntil < 1
      ? `en ${Math.round(hoursUntil * 60)} minutos`
      : `en ${hoursUntil} horas`;

  // Email to client
  const clientHtml = gardenEmail(
    `${booking.petName} tiene ${svc.toLowerCase()} ${timeLabel} ⏰`,
    `<p style="color:#555;font-size:14px;margin:0 0 20px;">Hola <strong>${clientName}</strong>, ${timeLabel} le toca ${svc.toLowerCase()} a <strong>${booking.petName}</strong> con <strong>${caregiverName}</strong>.</p>` +
    bookingTable([
      ['Servicio', svc],
      ['Cuidador', caregiverName],
      ['Mascota', booking.petName],
      ['Fecha', dates],
      ['ID de reserva', bookingId.slice(0, 8).toUpperCase()],
    ]) +
    `<p style="color:#555;font-size:14px;margin:0;">Coordina con ${caregiverName} la hora y el punto de entrega de ${booking.petName} por el chat de la app. 🐾</p>`
  );
  fireEmail(booking.client.email, `${booking.petName}: ${svc.toLowerCase()} ${timeLabel} – GARDEN`, clientHtml, 'SERVICE_REMINDER_CLIENT', bookingId);
  sendWhatsAppPlaceholder(booking.client.phone, `GARDEN: ${booking.petName} tiene ${svc.toLowerCase()} con ${caregiverName} ${timeLabel}. ID: ${bookingId.slice(0, 8).toUpperCase()}.`, { event: 'SERVICE_REMINDER_CLIENT', bookingId });

  // Email to caregiver
  if (booking.caregiver?.user) {
    const caregiverHtml = gardenEmail(
      `Recibes a ${booking.petName} ${timeLabel} ⏰`,
      `<p style="color:#555;font-size:14px;margin:0 0 20px;">Hola <strong>${caregiverName}</strong>, ${timeLabel} arranca el ${svc.toLowerCase()} de <strong>${booking.petName}</strong>, reservado por <strong>${clientName}</strong>.</p>` +
      bookingTable([
        ['Servicio', svc],
        ['Cliente', clientName],
        ['Mascota', booking.petName],
        ['Fecha', dates],
        ['ID de reserva', bookingId.slice(0, 8).toUpperCase()],
      ]) +
      `<p style="color:#555;font-size:14px;margin:0;">Confirma con ${clientName} el punto y la hora de recepción de ${booking.petName} por el chat. ¡Mucho éxito! 🌿</p>`
    );
    fireEmail(booking.caregiver.user.email, `${booking.petName} llega ${timeLabel} – GARDEN`, caregiverHtml, 'SERVICE_REMINDER_CAREGIVER', bookingId);
    sendWhatsAppPlaceholder(booking.caregiver.user.phone, `GARDEN: Recibes a ${booking.petName} para ${svc.toLowerCase()} ${timeLabel}. ID: ${bookingId.slice(0, 8).toUpperCase()}.`, { event: 'SERVICE_REMINDER_CAREGIVER', bookingId });
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
  const guideUrl = 'https://gardenbo.com/app.html#/guia-cuidador';

  const html = gardenEmail(
    `¡Bienvenido a GARDEN, ${caregiverName}! 🌿`,
    `<p style="color:#555;font-size:14px;margin:0 0 16px;">
      Hola <strong>${caregiverName}</strong>, tu perfil quedó aprobado — desde ahora ya puedes recibir solicitudes de paseo, guardería y hospedaje en tu zona. 🎉
    </p>
    <p style="color:#555;font-size:14px;margin:0 0 20px;">
      Estas primeras semanas son clave para armar tu reputación en el marketplace, así que vale la pena dejar todo bien configurado desde el día uno.
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
        📱 WhatsApp: <a href="https://wa.me/59175933133" style="color:#16a34a;text-decoration:none;">+591 75933133</a>
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
      message: `${caregiverName}, tu perfil ya está activo y visible. Lee la guía del cuidador para configurar disponibilidad, tarifas y empezar a recibir reservas.`,
      type: 'CAREGIVER_WELCOME',
    },
  });
}

/**
 * Un admin agregó o amplió un polígono de zona y el perfil de este usuario
 * (cliente o cuidador), que estaba en el caso excepcional de "sin zona"
 * (registrado igual, pero sin poder reservar), ahora sí cae dentro de una
 * zona cubierta. Aviso cálido, sin tecnicismos — solo la buena noticia.
 */
export async function onZoneNowAvailable(userId: string): Promise<void> {
  try {
    const user = await prisma.user.findUnique({ where: { id: userId }, select: { firstName: true } });
    const title = '¡Ya llegamos a tu zona! 🌿';
    const message = user?.firstName
      ? `${user.firstName}, ya tenemos cobertura en tu zona — puedes reservar servicios en GARDEN cuando quieras.`
      : 'Ya tenemos cobertura en tu zona — puedes reservar servicios en GARDEN cuando quieras.';
    await prisma.notification.create({ data: { userId, title, message, type: 'ZONE_NOW_AVAILABLE' } });
    sendPushToUser(userId, title, message).catch(() => {});
  } catch (err: any) {
    logger.error('[NOTIFICATION] onZoneNowAvailable error', { userId, error: err.message });
  }
}

/**
 * Recordatorio de capacitación AMATEUR obligatoria pendiente. Llamado por el
 * job diario (training-reminder.job.ts) — la notificación in-app + push se
 * reenvía cada día que siga pendiente; el correo (sendEmail=true) solo la
 * primera vez, el caller decide eso mirando trainingReminderEmailSentAt.
 */
export async function onTrainingReminder(userId: string, pendingTitles: string[], sendEmail: boolean): Promise<void> {
  const user = await prisma.user.findUnique({
    where: { id: userId },
    select: { email: true, firstName: true, lastName: true },
  });
  if (!user) {
    logger.warn('[NOTIFICATION] onTrainingReminder: user not found', { userId });
    return;
  }

  const caregiverName = name(user.firstName, user.lastName, 'Cuidador');
  const trainingsUrl = 'https://gardenbo.com/app.html#/caregiver/trainings';
  const list = pendingTitles.map((t) => `<li>${t}</li>`).join('');
  const firstPending = pendingTitles[0];
  const title = pendingTitles.length === 1
    ? `Te falta "${firstPending}"`
    : `Te faltan ${pendingTitles.length} capacitaciones`;
  const message = pendingTitles.length === 1
    ? `Completa "${firstPending}" para que tu perfil quede visible y puedas recibir tu primera reserva.`
    : `Empieza por "${firstPending}" (y ${pendingTitles.length - 1} más) para que tu perfil quede visible.`;

  await prisma.notification.create({
    data: { userId, title, message, type: 'TRAINING_REMINDER' },
  });
  sendPushToUser(userId, title, message).catch((err) =>
    logger.error('[NOTIFICATION] onTrainingReminder push failed', { userId, err })
  );

  if (sendEmail) {
    const html = gardenEmail(
      `${caregiverName}, tu perfil está invisible hasta completar esto 📋`,
      `<p style="color:#555;font-size:14px;margin:0 0 16px;">
        Hola <strong>${caregiverName}</strong>, tu perfil de cuidador ya está armado, pero todavía no aparece
        para los clientes porque te faltan estas capacitaciones (un video corto + 3 preguntas cada una):
      </p>
      <ul style="color:#166534;font-size:14px;margin:0 0 20px;padding-left:20px;line-height:1.9;">${list}</ul>
      <p style="color:#555;font-size:14px;margin:0 0 4px;">
        En cuanto las completes, quedas visible en el marketplace y puedes empezar a recibir solicitudes.
      </p>` +
      ctaButton('Completar capacitaciones 📋', trainingsUrl)
    );
    fireEmail(user.email, `${caregiverName}, completa tus capacitaciones – GARDEN`, html, 'TRAINING_REMINDER');
  }
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
    `Novedad sobre el reembolso de ${booking.petName} 💰`,
    `<p style="color:#555;font-size:14px;margin:0 0 20px;">Hola <strong>${clientName}</strong>, esto es lo que pasó con el reembolso de la reserva de <strong>${svc}</strong> para <strong>${booking.petName}</strong>.</p>` +
    bookingTable([
      ['Servicio', svc],
      ['Mascota', booking.petName],
      ['ID de reserva', bookingId.slice(0, 8).toUpperCase()],
    ]) +
    `<div style="background:#f0fdf4;border:1px solid #bbf7d0;border-radius:10px;padding:16px;margin:0 0 20px;">
       <p style="color:#166534;font-size:14px;margin:0;">${message}</p>
     </div>
     <p style="color:#555;font-size:14px;margin:0;">Si necesitas más detalles sobre este reembolso, escríbenos por el chat de soporte de la app y seguimos desde ahí. 🌿</p>`
  );

  fireEmail(booking.client.email, `Reembolso de ${booking.petName}: novedades – GARDEN`, html, 'REFUND_PROCESSED_CLIENT', bookingId);
  sendWhatsAppPlaceholder(
    booking.client.phone,
    `GARDEN: Sobre el reembolso de ${booking.petName} (${svc}) — ${message}`,
    { event: 'REFUND_PROCESSED_CLIENT', bookingId }
  );
}
