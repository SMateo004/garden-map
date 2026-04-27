import prisma from '../../config/database.js';
import { AppError } from '../../shared/errors.js';
import logger from '../../shared/logger.js';
import { getIO } from '../../services/socket.service.js';

async function sendSystemChatMessage(bookingId: string, senderId: string, message: string) {
  try {
    const saved = await prisma.chatMessage.create({
      data: {
        bookingId,
        senderId,
        senderRole: 'SYSTEM',
        message,
        isSystem: true,
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

async function sendNotif(userId: string, title: string, body: string) {
  try {
    await prisma.notification.create({
      data: { userId, title, message: body, type: 'SYSTEM' },
    });
  } catch (e) {
    logger.warn('[MG] Notification FAILED', { userId, error: e });
  }
}

export async function getMeetAndGreet(bookingId: string) {
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

  // Funciona para PASEO y HOSPEDAJE
  // Permitido en WAITING_CAREGIVER_APPROVAL y CONFIRMED
  const allowedStatuses = ['WAITING_CAREGIVER_APPROVAL', 'CONFIRMED'];
  if (!allowedStatuses.includes(booking.status)) {
    logger.warn('[MG] propose() blocked — invalid status', { bookingId, status: booking.status });
    throw new AppError(
      `La reserva debe estar en espera de aprobación o confirmada (estado actual: ${booking.status})`,
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

  await sendSystemChatMessage(bookingId, proposedBy, chatMsg);

  if (otherId) {
    await sendNotif(otherId, 'Meet & Greet propuesto',
      `Te propusieron un Meet & Greet para el ${dateLabel}${timeLabel ? ` a las ${timeLabel}` : ''}`);
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
    '¡Tu propuesta de Meet & Greet fue aceptada!'
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
    `✅ Meet & Greet confirmado${dateLabel ? ` · ${dateLabel}` : ''}`
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
      'El cuidador detectó incompatibilidad. Tu reserva fue cancelada y recibirás reembolso completo.'
    );
    await sendSystemChatMessage(
      bookingId, caregiverUserIdParam,
      '❌ Meet & Greet finalizado · El cuidador detectó incompatibilidad. La reserva fue cancelada con reembolso completo.'
    );
  } else {
    await sendNotif(
      booking.clientId,
      'Meet & Greet completado',
      '¡El cuidador confirmó compatibilidad! Ya puedes continuar con tu reserva.'
    );
    await sendSystemChatMessage(
      bookingId, caregiverUserIdParam,
      '✅ Meet & Greet finalizado · ¡Todo compatible! El cuidador está listo para el servicio.'
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
    await sendNotif(otherId, 'Meet & Greet cancelado', 'El Meet & Greet fue cancelado.');
  }

  await sendSystemChatMessage(bookingId, userId, '🚫 Meet & Greet cancelado');

  logger.info('[MG] cancel() → CANCELLED', { bookingId });
  return mg;
}
