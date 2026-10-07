import prisma from '../../config/database.js';
import { AppError } from '../../shared/errors.js';
import logger from '../../shared/logger.js';
import { getIO } from '../../services/socket.service.js';

/** Tipos de mensaje de sistema que entiende la app (narrative/chat_event.dart). */
type SystemEventType = 'MG_PROPOSED' | 'MG_CONFIRMED' | 'MG_COMPATIBLE' | 'MG_INCOMPATIBLE' | 'MG_CANCELLED';

async function sendSystemChatMessage(bookingId: string, senderId: string, message: string, eventType: SystemEventType) {
  try {
    const saved = await prisma.chatMessage.create({
      data: {
        bookingId,
        senderId,
        senderRole: 'SYSTEM',
        message,
        isSystem: true,
        eventType,
      },
    });
    logger.info('[MG] System chat message saved', { bookingId, msgId: saved.id, preview: message.slice(0, 60) });

    // Emit via Socket.IO so connected clients see the message in real-time
    try {
      const io = getIO();
      if (!io) { logger.warn('[MG] Socket not ready, skipping emit', { bookingId }); return; }
      io.to(`booking:${bookingId}`).emit('new_message', {
        id: saved.id,
        bookingId: saved.bookingId,
        senderId: saved.senderId,
        senderName: 'Sistema',
        senderRole: 'SYSTEM',
        message: saved.message,
        isSystem: true,
        eventType: saved.eventType,
        read: saved.read,
        createdAt: saved.createdAt.toISOString(),
      });
      logger.info('[MG] Socket emit new_message OK', { bookingId, room: `booking:${bookingId}` });
    } catch (socketErr) {
      logger.warn('[MG] Socket emit failed (non-fatal)', { bookingId, error: socketErr });
    }
  } catch (e) {
    logger.warn('[MG] System chat message FAILED', { bookingId, error: e });
  }
}

async function sendNotif(userId: string, title: string, body: string, bookingId?: string) {
  try {
    await prisma.notification.create({
      data: { userId, title, message: body, type: 'SYSTEM', bookingId },
    });
  } catch (e) {
    logger.warn('[MG] Notification FAILED', { userId, error: e });
  }
}

/**
 * Solo el cliente o el cuidador DE ESA RESERVA pueden proponer/aceptar/
 * cancelar su Meet & Greet. Antes solo se validaba "no aceptes tu propia
 * propuesta" — cualquier otro usuario autenticado del sistema (ajeno a la
 * reserva) podía proponer, aceptar o cancelar el M&G de una reserva que no
 * le pertenecía, ya que las rutas solo exigen estar logueado (authMiddleware),
 * sin requireRole ni verificación de pertenencia.
 */
function assertBelongsToBooking(booking: { clientId: string; caregiver: { userId: string } }, userId: string) {
  if (userId !== booking.clientId && userId !== booking.caregiver.userId) {
    throw new AppError('No tienes acceso a esta reserva', 403, 'FORBIDDEN');
  }
}

// FIX (auditoría 2026-10-02): a diferencia de propose/accept/reschedule/complete/cancel
// (todos ya protegidos por assertBelongsToBooking, ver comentario de esa función), este
// endpoint no validaba pertenencia — cualquier usuario autenticado del sistema podía leer
// el Meet & Greet de CUALQUIER reserva (fecha, modalidad y, para IN_PERSON, la dirección
// física del punto de encuentro) solo con adivinar/enumerar un bookingId.
export async function getMeetAndGreet(bookingId: string, userId: string) {
  const booking = await prisma.booking.findUnique({
    where: { id: bookingId },
    include: { caregiver: { select: { userId: true } } },
  });
  if (!booking) throw new AppError('Reserva no encontrada', 404, 'NOT_FOUND');
  assertBelongsToBooking(booking, userId);

  return prisma.meetAndGreet.findUnique({ where: { bookingId } });
}

export async function propose(bookingId: string, proposedBy: string, body: {
  modalidad: 'IN_PERSON' | 'VIDEO_CALL';
  proposedDate: string;
  meetingPoint: string;
  note?: string;
}) {
  logger.info('[MG] propose() called', { bookingId, proposedBy, body });

  const booking = await prisma.booking.findUnique({
    where: { id: bookingId },
    include: {
      meetAndGreet: true,
      caregiver: { select: { userId: true } },
    },
  });

  if (!booking) throw new AppError('Reserva no encontrada', 404, 'NOT_FOUND');
  assertBelongsToBooking(booking, proposedBy);

  // Funciona para PASEO y HOSPEDAJE
  // El Meet & Greet solo tiene sentido ANTES de que el cuidador acepte la
  // reserva — una vez que el cuidador ya aceptó (CONFIRMED) o el servicio
  // arrancó (IN_PROGRESS), ya no se puede solicitar.
  const allowedStatuses = ['WAITING_CAREGIVER_APPROVAL'];
  if (!allowedStatuses.includes(booking.status)) {
    logger.warn('[MG] propose() blocked — invalid status', { bookingId, status: booking.status });
    throw new AppError(
      `El Meet & Greet solo se puede solicitar antes de que el cuidador acepte la reserva (estado actual: ${booking.status})`,
      400, 'BAD_REQUEST'
    );
  }

  if (!body.meetingPoint || body.meetingPoint.trim() === '') {
    throw new AppError('El punto de encuentro es obligatorio', 400, 'VALIDATION_ERROR');
  }

  const proposedDate = new Date(body.proposedDate);
  if (isNaN(proposedDate.getTime())) {
    throw new AppError('Fecha inválida', 400, 'BAD_REQUEST');
  }
  if (proposedDate.getTime() <= Date.now()) {
    throw new AppError('La fecha del Meet & Greet debe ser en el futuro', 400, 'BAD_REQUEST');
  }
  // El M&G debe ocurrir ANTES de que empiece el servicio — antes no se
  // validaba esto: se podía proponer una fecha durante o después del
  // hospedaje/paseo ya reservado, lo cual no tiene sentido (el propósito
  // es conocerse ANTES de que el servicio comience).
  const serviceDate = (booking as any).startDate ?? (booking as any).walkDate;
  if (serviceDate && proposedDate.getTime() >= new Date(serviceDate).getTime()) {
    throw new AppError('El Meet & Greet debe ser antes de la fecha del servicio reservado', 400, 'BAD_REQUEST');
  }

  let mg;
  if (booking.meetAndGreet) {
    mg = await prisma.meetAndGreet.update({
      where: { bookingId },
      data: {
        status: 'PROPOSED',
        proposedBy,
        modalidad: body.modalidad,
        proposedDate,
        meetingPoint: body.meetingPoint.trim(),
        confirmedDate: null,
      },
    });
    logger.info('[MG] Updated existing MeetAndGreet → PROPOSED', { bookingId });
  } else {
    mg = await prisma.meetAndGreet.create({
      data: {
        bookingId,
        proposedBy,
        modalidad: body.modalidad,
        proposedDate,
        meetingPoint: body.meetingPoint.trim(),
        status: 'PROPOSED',
      },
    });
    logger.info('[MG] Created new MeetAndGreet → PROPOSED', { bookingId });
  }

  // Notificar a la otra parte
  const caregiverUserId = booking.caregiver.userId;
  const otherId = proposedBy === caregiverUserId ? booking.clientId : caregiverUserId;

  const dateLabel = proposedDate.toLocaleDateString('es-ES', {
    weekday: 'long', day: 'numeric', month: 'long',
  });
  // Hora local: ISO string puede venir como "2026-04-30T15:00:00" → "15:00"
  const timeLabel = body.proposedDate.includes('T')
    ? body.proposedDate.split('T')[1]?.slice(0, 5) ?? ''
    : '';
  const modalidadLabel = body.modalidad === 'IN_PERSON' ? 'Presencial' : 'Videollamada';

  // Mensaje estructurado en el chat — el prefijo 📋 es lo que Flutter detecta para el card especial
  const chatMsg = [
    '📋 MEET & GREET PROPUESTO',
    `📅 ${dateLabel}${timeLabel ? ` · ${timeLabel}` : ''}`,
    `📍 ${body.meetingPoint.trim()}`,
    `🤝 ${modalidadLabel}`,
  ].join('\n');

  await sendSystemChatMessage(bookingId, proposedBy, chatMsg, 'MG_PROPOSED');

  if (otherId) {
    await sendNotif(otherId, 'Meet & Greet propuesto',
      `Te propusieron un Meet & Greet para el ${dateLabel}${timeLabel ? ` a las ${timeLabel}` : ''}`, bookingId);
  }

  logger.info('[MG] propose() done', { bookingId, mgId: mg.id, status: mg.status });
  return mg;
}

export async function accept(bookingId: string, userId: string) {
  logger.info('[MG] accept() called', { bookingId, userId });

  const booking = await prisma.booking.findUnique({
    where: { id: bookingId },
    include: {
      meetAndGreet: true,
      caregiver: { select: { userId: true } },
    },
  });
  if (!booking?.meetAndGreet) throw new AppError('No hay propuesta de Meet & Greet', 404, 'NOT_FOUND');
  assertBelongsToBooking(booking, userId);
  if (booking.meetAndGreet.status !== 'PROPOSED') {
    throw new AppError('No hay propuesta pendiente', 400, 'BAD_REQUEST');
  }
  if (booking.meetAndGreet.proposedBy === userId) {
    throw new AppError('No puedes aceptar tu propia propuesta', 400, 'BAD_REQUEST');
  }

  const mg = await prisma.meetAndGreet.update({
    where: { bookingId },
    data: {
      status: 'ACCEPTED',
      confirmedDate: booking.meetAndGreet.proposedDate,
    },
  });

  logger.info('[MG] accept() → ACCEPTED', { bookingId, confirmedDate: mg.confirmedDate });

  await sendNotif(
    booking.meetAndGreet.proposedBy,
    'Meet & Greet aceptado',
    '¡Tu propuesta de Meet & Greet fue aceptada!', bookingId
  );

  const dateLabel = mg.confirmedDate
    ? mg.confirmedDate.toLocaleDateString('es-ES', {
        weekday: 'long', day: 'numeric', month: 'long',
        hour: '2-digit', minute: '2-digit',
      })
    : '';

  await sendSystemChatMessage(
    bookingId,
    userId,
    `✅ Meet & Greet confirmado${dateLabel ? ` · ${dateLabel}` : ''}`,
    'MG_CONFIRMED',
  );

  return mg;
}

export async function reschedule(bookingId: string, proposedBy: string, body: {
  modalidad: 'IN_PERSON' | 'VIDEO_CALL';
  proposedDate: string;
  meetingPoint: string;
  note?: string;
}) {
  logger.info('[MG] reschedule() → delegating to propose()', { bookingId });
  return propose(bookingId, proposedBy, body);
}

export async function complete(bookingId: string, caregiverUserIdParam: string, body: {
  caregiverNotes?: string;
  approved: boolean;
}) {
  logger.info('[MG] complete() called', { bookingId, caregiverUserIdParam, approved: body.approved });

  const booking = await prisma.booking.findUnique({
    where: { id: bookingId },
    include: {
      meetAndGreet: true,
      caregiver: { select: { userId: true } },
    },
  });
  if (!booking?.meetAndGreet) throw new AppError('Meet & Greet no encontrado', 404, 'NOT_FOUND');
  if (booking.meetAndGreet.status !== 'ACCEPTED') {
    throw new AppError('El Meet & Greet debe estar aceptado primero', 400, 'BAD_REQUEST');
  }
  if (booking.caregiver.userId !== caregiverUserIdParam) {
    throw new AppError('Solo el cuidador puede completar el Meet & Greet', 403, 'FORBIDDEN');
  }

  const mg = await prisma.meetAndGreet.update({
    where: { bookingId },
    data: {
      status: 'COMPLETED',
      caregiverNotes: body.caregiverNotes,
      approved: body.approved,
    },
  });

  logger.info('[MG] complete() → COMPLETED', { bookingId, approved: body.approved });

  if (!body.approved) {
    await prisma.booking.update({
      where: { id: bookingId },
      data: {
        status: 'CANCELLED',
        cancellationReason: 'Incompatibilidad detectada en Meet & Greet',
      },
    });
    await sendNotif(
      booking.clientId,
      'Meet & Greet: incompatibilidad',
      'El cuidador detectó incompatibilidad. Tu reserva fue cancelada y recibirás reembolso completo.', bookingId
    );
    await sendSystemChatMessage(
      bookingId, caregiverUserIdParam,
      '❌ Meet & Greet finalizado · El cuidador detectó incompatibilidad. La reserva fue cancelada con reembolso completo.',
      'MG_INCOMPATIBLE',
    );
  } else {
    await sendNotif(
      booking.clientId,
      'Meet & Greet completado',
      '¡El cuidador confirmó compatibilidad! Ya puedes continuar con tu reserva.', bookingId
    );
    await sendSystemChatMessage(
      bookingId, caregiverUserIdParam,
      '✅ Meet & Greet finalizado · ¡Todo compatible! El cuidador está listo para el servicio.',
      'MG_COMPATIBLE',
    );
  }

  return mg;
}

export async function cancel(bookingId: string, userId: string) {
  logger.info('[MG] cancel() called', { bookingId, userId });

  const booking = await prisma.booking.findUnique({
    where: { id: bookingId },
    include: {
      meetAndGreet: true,
      caregiver: { select: { userId: true } },
    },
  });
  if (!booking?.meetAndGreet) throw new AppError('Meet & Greet no encontrado', 404, 'NOT_FOUND');
  assertBelongsToBooking(booking, userId);
  if (!['PROPOSED', 'ACCEPTED'].includes(booking.meetAndGreet.status)) {
    throw new AppError('No se puede cancelar en este estado', 400, 'BAD_REQUEST');
  }

  const mg = await prisma.meetAndGreet.update({
    where: { bookingId },
    data: { status: 'CANCELLED' },
  });

  const caregiverUserId = booking.caregiver.userId;
  const otherId = userId === caregiverUserId ? booking.clientId : caregiverUserId;
  if (otherId) {
    await sendNotif(otherId, 'Meet & Greet cancelado', 'El Meet & Greet fue cancelado.', bookingId);
  }

  await sendSystemChatMessage(bookingId, userId, '🚫 Meet & Greet cancelado', 'MG_CANCELLED');

  logger.info('[MG] cancel() → CANCELLED', { bookingId });
  return mg;
}
