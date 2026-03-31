import prisma from '../../config/database.js';
import { AppError } from '../../shared/errors.js';
import logger from '../../shared/logger.js';

async function sendSystemChatMessage(bookingId: string, senderId: string, message: string) {
  try {
    await prisma.chatMessage.create({
      data: {
        bookingId,
        senderId,
        senderRole: 'SYSTEM',
        message,
        isSystem: true,
      },
    });
  } catch (e) {
    logger.warn('Meet&Greet system chat message failed', { bookingId, error: e });
  }
}

async function sendNotif(userId: string, title: string, body: string) {
  try {
    await prisma.notification.create({
      data: {
        userId,
        title,
        message: body,
        type: 'SYSTEM',
      },
    });
  } catch (e) {
    logger.warn('Meet&Greet notification failed', { userId, error: e });
  }
}

export async function getMeetAndGreet(bookingId: string) {
  return prisma.meetAndGreet.findUnique({
    where: { bookingId },
  });
}

export async function propose(bookingId: string, proposedBy: string, body: {
  modalidad: 'IN_PERSON' | 'VIDEO_CALL';
  proposedDate: string;
  meetingPoint: string;
  note?: string;
}) {
  const booking = await prisma.booking.findUnique({
    where: { id: bookingId },
    include: {
      meetAndGreet: true,
      caregiver: { select: { userId: true } },
    },
  });
  if (!booking) throw new AppError('Reserva no encontrada', 404, 'NOT_FOUND');
  if (booking.serviceType !== 'HOSPEDAJE') throw new AppError('Meet & Greet solo aplica a hospedajes', 400, 'BAD_REQUEST');
  if (booking.status !== 'CONFIRMED') throw new AppError('La reserva debe estar confirmada', 400, 'BAD_REQUEST');
  if (!body.meetingPoint || body.meetingPoint.trim() === '') throw new AppError('El punto de encuentro es obligatorio', 400, 'VALIDATION_ERROR');

  const proposedDate = new Date(body.proposedDate);
  if (isNaN(proposedDate.getTime())) throw new AppError('Fecha inválida', 400, 'BAD_REQUEST');

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
  }

  // Notify the other party
  const caregiverUserId = booking.caregiver.userId;
  const otherId = proposedBy === caregiverUserId ? booking.clientId : caregiverUserId;
  if (otherId) {
    const dateLabel = proposedDate.toLocaleDateString('es-ES', { weekday: 'long', day: 'numeric', month: 'long' });
    await sendNotif(otherId, 'Meet & Greet propuesto', `Te propusieron un Meet & Greet para el ${dateLabel}`);
  }

  return mg;
}

export async function accept(bookingId: string, userId: string) {
  const booking = await prisma.booking.findUnique({
    where: { id: bookingId },
    include: {
      meetAndGreet: true,
      caregiver: { select: { userId: true } },
    },
  });
  if (!booking?.meetAndGreet) throw new AppError('No hay propuesta de Meet & Greet', 404, 'NOT_FOUND');
  if (booking.meetAndGreet.status !== 'PROPOSED') throw new AppError('No hay propuesta pendiente', 400, 'BAD_REQUEST');
  if (booking.meetAndGreet.proposedBy === userId) throw new AppError('No puedes aceptar tu propia propuesta', 400, 'BAD_REQUEST');

  const mg = await prisma.meetAndGreet.update({
    where: { bookingId },
    data: {
      status: 'ACCEPTED',
      confirmedDate: booking.meetAndGreet.proposedDate,
    },
  });

  await sendNotif(booking.meetAndGreet.proposedBy, 'Meet & Greet aceptado', '¡Tu propuesta de Meet & Greet fue aceptada!');

  // Mensaje de sistema en el chat
  const dateLabel = mg.confirmedDate
    ? mg.confirmedDate.toLocaleDateString('es-ES', { weekday: 'long', day: 'numeric', month: 'long', hour: '2-digit', minute: '2-digit' })
    : '';
  await sendSystemChatMessage(
    bookingId,
    userId,
    `🤝 Meet & Greet confirmado${dateLabel ? ` · ${dateLabel}` : ''}`
  );

  return mg;
}

export async function reschedule(bookingId: string, proposedBy: string, body: {
  modalidad: 'IN_PERSON' | 'VIDEO_CALL';
  proposedDate: string;
  meetingPoint: string;
  note?: string;
}) {
  return propose(bookingId, proposedBy, body);
}

export async function complete(bookingId: string, caregiverUserIdParam: string, body: {
  caregiverNotes?: string;
  approved: boolean;
}) {
  const booking = await prisma.booking.findUnique({
    where: { id: bookingId },
    include: {
      meetAndGreet: true,
      caregiver: { select: { userId: true } },
    },
  });
  if (!booking?.meetAndGreet) throw new AppError('Meet & Greet no encontrado', 404, 'NOT_FOUND');
  if (booking.meetAndGreet.status !== 'ACCEPTED') throw new AppError('El Meet & Greet debe estar aceptado primero', 400, 'BAD_REQUEST');
  if (booking.caregiver.userId !== caregiverUserIdParam) throw new AppError('Solo el cuidador puede completar el Meet & Greet', 403, 'FORBIDDEN');

  const mg = await prisma.meetAndGreet.update({
    where: { bookingId },
    data: {
      status: 'COMPLETED',
      caregiverNotes: body.caregiverNotes,
      approved: body.approved,
    },
  });

  if (!body.approved) {
    await prisma.booking.update({
      where: { id: bookingId },
      data: {
        status: 'CANCELLED',
        cancellationReason: 'Incompatibilidad detectada en Meet & Greet',
      },
    });
    await sendNotif(booking.clientId, 'Meet & Greet: incompatibilidad', 'El cuidador detectó incompatibilidad. Tu reserva fue cancelada y recibirás reembolso completo.');
    await sendSystemChatMessage(bookingId, caregiverUserIdParam, '❌ Meet & Greet finalizado · El cuidador detectó incompatibilidad. La reserva fue cancelada y recibirás reembolso completo.');
  } else {
    await sendNotif(booking.clientId, 'Meet & Greet completado', 'El cuidador confirmó compatibilidad. ¡Tu hospedaje está listo!');
    await sendSystemChatMessage(bookingId, caregiverUserIdParam, '✅ Meet & Greet finalizado · ¡Todo compatible! El hospedaje está confirmado.');
  }

  return mg;
}

export async function cancel(bookingId: string, userId: string) {
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

  return mg;
}
