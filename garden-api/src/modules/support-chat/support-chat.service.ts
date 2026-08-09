import prisma from '../../config/database.js';
import { BadRequestError } from '../../shared/errors.js';
import { getIO } from '../../services/socket.service.js';
import logger from '../../shared/logger.js';

const MAX_MESSAGE_LENGTH = 2000;
const PREVIEW_LENGTH = 200;

function preview(message: string): string {
  return message.length > PREVIEW_LENGTH ? `${message.slice(0, PREVIEW_LENGTH - 1)}…` : message;
}

/** Todos los admins conectados están en esta sala (ver socket.service.ts) —
 * así el inbox del admin se actualiza en vivo sin pollear. */
const ADMIN_SUPPORT_ROOM = 'admin:support';

function validateMessage(message: unknown): string {
  if (typeof message !== 'string' || !message.trim()) {
    throw new BadRequestError('El mensaje no puede estar vacío', 'EMPTY_MESSAGE');
  }
  const trimmed = message.trim();
  if (trimmed.length > MAX_MESSAGE_LENGTH) {
    throw new BadRequestError(`El mensaje no puede superar ${MAX_MESSAGE_LENGTH} caracteres`, 'MESSAGE_TOO_LONG');
  }
  return trimmed;
}

/** Cliente envía un mensaje — crea el hilo si es la primera vez que escribe
 * (userId es @unique en SupportThread, así que solo existe UNO por cliente
 * en toda su vida en Garden, sin importar cuántas veces cierre la app). */
export async function sendClientMessage(userId: string, rawMessage: string) {
  const message = validateMessage(rawMessage);

  const thread = await prisma.supportThread.upsert({
    where: { userId },
    create: { userId, lastMessagePreview: preview(message), unreadByAdmin: true },
    update: { lastMessageAt: new Date(), lastMessagePreview: preview(message), unreadByAdmin: true },
  });

  const saved = await prisma.supportMessage.create({
    data: { threadId: thread.id, senderRole: 'CLIENT', message },
  });

  const client = await prisma.user.findUnique({
    where: { id: userId },
    select: { firstName: true, lastName: true, profilePicture: true },
  });

  const io = getIO();
  if (io) {
    io.to(ADMIN_SUPPORT_ROOM).emit('support_new_message', {
      threadId: thread.id,
      userId,
      clientName: client ? `${client.firstName} ${client.lastName}`.trim() : 'Cliente',
      clientPhoto: client?.profilePicture ?? null,
      message,
      createdAt: saved.createdAt.toISOString(),
    });
  }

  return { id: saved.id, threadId: thread.id, message: saved.message, createdAt: saved.createdAt };
}

/** Mensajes de la SESIÓN ACTUAL del cliente — todo lo creado desde `since`
 * en adelante (cliente y admin), sin importar mensajes previos a esa fecha.
 * El cliente calcula `since` una sola vez por arranque de la app (ver
 * SupportChatSession en Flutter) — así, cerrar y volver a abrir la app hace
 * que la conversación "empiece de cero" del lado del cliente, aunque en la
 * base el hilo real sigue completo para el admin. */
export async function getClientSessionMessages(userId: string, since: Date) {
  const thread = await prisma.supportThread.findUnique({ where: { userId } });
  if (!thread) return { threadId: null, messages: [] as unknown[] };

  const messages = await prisma.supportMessage.findMany({
    where: { threadId: thread.id, createdAt: { gte: since } },
    orderBy: { createdAt: 'asc' },
  });

  return {
    threadId: thread.id,
    messages: messages.map((m) => ({
      id: m.id,
      senderRole: m.senderRole,
      message: m.message,
      createdAt: m.createdAt.toISOString(),
    })),
  };
}

/** Inbox del admin — un renglón por cliente, como la lista de chats de
 * WhatsApp: nombre, último mensaje, cuándo, y si hay algo sin leer. */
export async function listThreadsForAdmin() {
  const threads = await prisma.supportThread.findMany({
    orderBy: { lastMessageAt: 'desc' },
    include: {
      user: { select: { id: true, firstName: true, lastName: true, profilePicture: true, role: true } },
    },
  });

  return threads.map((t) => ({
    threadId: t.id,
    userId: t.userId,
    clientName: `${t.user.firstName} ${t.user.lastName}`.trim(),
    clientPhoto: t.user.profilePicture ?? null,
    clientRole: t.user.role,
    lastMessageAt: t.lastMessageAt.toISOString(),
    lastMessagePreview: t.lastMessagePreview,
    unreadByAdmin: t.unreadByAdmin,
  }));
}

/** Historial COMPLETO de un hilo — vista del admin, nunca se filtra por sesión. */
export async function getThreadMessagesForAdmin(threadId: string) {
  const thread = await prisma.supportThread.findUnique({
    where: { id: threadId },
    include: { user: { select: { id: true, firstName: true, lastName: true, profilePicture: true } } },
  });
  if (!thread) throw new BadRequestError('Conversación no encontrada', 'THREAD_NOT_FOUND');

  const messages = await prisma.supportMessage.findMany({
    where: { threadId },
    orderBy: { createdAt: 'asc' },
  });

  return {
    threadId: thread.id,
    userId: thread.userId,
    clientName: `${thread.user.firstName} ${thread.user.lastName}`.trim(),
    clientPhoto: thread.user.profilePicture ?? null,
    messages: messages.map((m) => ({
      id: m.id,
      senderRole: m.senderRole,
      senderUserId: m.senderUserId,
      message: m.message,
      createdAt: m.createdAt.toISOString(),
    })),
  };
}

export async function sendAdminReply(adminUserId: string, threadId: string, rawMessage: string) {
  const message = validateMessage(rawMessage);

  const thread = await prisma.supportThread.findUnique({ where: { id: threadId } });
  if (!thread) throw new BadRequestError('Conversación no encontrada', 'THREAD_NOT_FOUND');

  const saved = await prisma.supportMessage.create({
    data: { threadId, senderRole: 'ADMIN', senderUserId: adminUserId, message },
  });

  await prisma.supportThread.update({
    where: { id: threadId },
    data: { lastMessageAt: new Date(), lastMessagePreview: preview(message), unreadByAdmin: false },
  });

  const io = getIO();
  if (io) {
    io.to(`user:${thread.userId}`).emit('support_admin_reply', {
      threadId,
      message,
      createdAt: saved.createdAt.toISOString(),
    });
    // Otros admins con el inbox abierto también ven la respuesta reflejada al instante.
    io.to(ADMIN_SUPPORT_ROOM).emit('support_thread_updated', { threadId, lastMessagePreview: preview(message) });
  }

  return { id: saved.id, threadId, message: saved.message, createdAt: saved.createdAt };
}

export async function markThreadReadByAdmin(threadId: string) {
  await prisma.supportThread.updateMany({ where: { id: threadId }, data: { unreadByAdmin: false } }).catch((err) => {
    logger.error('[SUPPORT_CHAT] Error marcando hilo como leído', { threadId, err });
  });
}
