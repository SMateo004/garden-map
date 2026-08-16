import prisma from '../../config/database.js';
import { BadRequestError } from '../../shared/errors.js';
import { getIO } from '../../services/socket.service.js';
import logger from '../../shared/logger.js';
import { responderSoporte, type MensajeHistorial } from '../../agents/soporte-chat.agent.js';

const MAX_MESSAGE_LENGTH = 2000;
const PREVIEW_LENGTH = 200;
// Cuántos mensajes previos se le pasan al bot como contexto — suficiente
// para que no pierda el hilo, sin inflar el costo de cada llamada a Claude.
const BOT_HISTORY_WINDOW = 20;

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
 * en toda su vida en Garden). Si el hilo estaba RESOLVED, este mensaje lo
 * reabre como una conversación nueva (ver resolvedAt en getClientSessionMessages).
 *
 * El bot (Claude, grounded en el centro de ayuda) responde automáticamente
 * salvo que un admin ya haya entrado de verdad al hilo (adminJoinedAt seteado)
 * — ahí se calla para no pisarse con la persona real. Si el bot decide que
 * hace falta un humano (o una de las reglas duras de escalación aplica), el
 * hilo pasa a ESCALATED y se notifica al admin — recién ahí, nunca antes.
 */
export async function sendClientMessage(userId: string, rawMessage: string) {
  const message = validateMessage(rawMessage);

  const existing = await prisma.supportThread.findUnique({ where: { userId } });
  const isReopening = existing?.status === 'RESOLVED';

  const thread = await prisma.supportThread.upsert({
    where: { userId },
    create: { userId, lastMessagePreview: preview(message), unreadByAdmin: true },
    update: isReopening
      ? {
          // Reabrir: nueva conversación visual para el cliente, pero el
          // historial completo sigue existiendo en la base para el admin.
          lastMessageAt: new Date(),
          lastMessagePreview: preview(message),
          unreadByAdmin: true,
          status: 'BOT',
          adminJoinedAt: null,
        }
      : { lastMessageAt: new Date(), lastMessagePreview: preview(message), unreadByAdmin: true },
  });

  const saved = await prisma.supportMessage.create({
    data: { threadId: thread.id, senderRole: 'CLIENT', message },
  });

  const client = await prisma.user.findUnique({
    where: { id: userId },
    select: { firstName: true, lastName: true, profilePicture: true },
  });

  const io = getIO();

  // El bot responde salvo que un admin ya esté activamente en el hilo.
  let botMessage: { id: string; message: string; createdAt: Date } | null = null;
  if (!thread.adminJoinedAt) {
    const historyRows = await prisma.supportMessage.findMany({
      where: { threadId: thread.id },
      orderBy: { createdAt: 'desc' },
      take: BOT_HISTORY_WINDOW,
      select: { senderRole: true, message: true },
    });
    const historial: MensajeHistorial[] = historyRows
      .reverse()
      .slice(0, -1) // el mensaje que acabamos de guardar ya va aparte como "nuevoMensaje"
      .map((m) => ({ senderRole: m.senderRole as MensajeHistorial['senderRole'], message: m.message }));

    const resultado = await responderSoporte({ historial, nuevoMensaje: message, userId });

    const savedBot = await prisma.supportMessage.create({
      data: { threadId: thread.id, senderRole: 'BOT', message: resultado.respuesta },
    });
    botMessage = { id: savedBot.id, message: savedBot.message, createdAt: savedBot.createdAt };

    if (resultado.necesitaHumano) {
      await prisma.supportThread.update({
        where: { id: thread.id },
        data: { status: 'ESCALATED', lastMessageAt: new Date(), lastMessagePreview: preview(resultado.respuesta) },
      });
      logger.info('[SupportChat] Hilo escalado a admin', { threadId: thread.id, userId, razon: resultado.razon });
    }
  }

  if (io) {
    io.to(ADMIN_SUPPORT_ROOM).emit('support_new_message', {
      threadId: thread.id,
      userId,
      clientName: client ? `${client.firstName} ${client.lastName}`.trim() : 'Cliente',
      clientPhoto: client?.profilePicture ?? null,
      message,
      createdAt: saved.createdAt.toISOString(),
    });
    // El bot responde por el mismo canal que usa una respuesta de admin —
    // el cliente no necesita distinguir el transporte, solo el remitente.
    if (botMessage) {
      io.to(`user:${userId}`).emit('support_admin_reply', {
        threadId: thread.id,
        message: botMessage.message,
        senderRole: 'BOT',
        createdAt: botMessage.createdAt.toISOString(),
      });
    }
  }

  return {
    id: saved.id,
    threadId: thread.id,
    message: saved.message,
    createdAt: saved.createdAt,
    botMessage,
  };
}

/** Mensajes de la conversación actual del cliente. Antes "empezaba de cero"
 * en cada apertura de la app (filtro por un timestamp local del cliente);
 * ahora la conversación persiste hasta que un admin la marca resuelta —
 * `resolvedAt` es la única frontera, y vive en el servidor, no en el
 * teléfono. Sin resolución previa, se devuelve el historial completo. */
export async function getClientSessionMessages(userId: string) {
  const thread = await prisma.supportThread.findUnique({ where: { userId } });
  if (!thread) return { threadId: null, status: 'BOT' as const, messages: [] as unknown[] };

  const messages = await prisma.supportMessage.findMany({
    where: {
      threadId: thread.id,
      ...(thread.resolvedAt ? { createdAt: { gt: thread.resolvedAt } } : {}),
    },
    orderBy: { createdAt: 'asc' },
  });

  return {
    threadId: thread.id,
    status: thread.status,
    messages: messages.map((m) => ({
      id: m.id,
      senderRole: m.senderRole,
      message: m.message,
      createdAt: m.createdAt.toISOString(),
    })),
  };
}

/** Inbox del admin — un renglón por cliente, como la lista de chats de
 * WhatsApp: nombre, último mensaje, cuándo, si hay algo sin leer, y el
 * estado (bot atendiendo / esperando asesor / resuelto). */
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
    status: t.status,
  }));
}

/** Historial COMPLETO de un hilo — vista del admin, nunca se filtra por
 * sesión. Efecto colateral intencional: si el hilo está ESCALATED y ningún
 * admin había entrado todavía, esto CUENTA como que un admin entró — se
 * marca adminJoinedAt, se apaga el bot para este hilo, y se deja un mensaje
 * visible para el cliente avisando que ya hay una persona atendiendo. Antes
 * de esto, nunca se le prometía al cliente una persona que no estaba ahí. */
export async function getThreadMessagesForAdmin(threadId: string) {
  const thread = await prisma.supportThread.findUnique({
    where: { id: threadId },
    include: { user: { select: { id: true, firstName: true, lastName: true, profilePicture: true } } },
  });
  if (!thread) throw new BadRequestError('Conversación no encontrada', 'THREAD_NOT_FOUND');

  if (thread.status === 'ESCALATED' && !thread.adminJoinedAt) {
    const joinedMessage = 'Un asesor humano se unió a la conversación y va a revisar tu caso.';
    const savedJoin = await prisma.supportMessage.create({
      data: { threadId, senderRole: 'ADMIN', message: joinedMessage },
    });
    await prisma.supportThread.update({ where: { id: threadId }, data: { adminJoinedAt: new Date() } });

    const io = getIO();
    if (io) {
      io.to(`user:${thread.userId}`).emit('support_admin_reply', {
        threadId,
        message: joinedMessage,
        senderRole: 'ADMIN',
        createdAt: savedJoin.createdAt.toISOString(),
      });
    }
    logger.info('[SupportChat] Admin entró al hilo escalado — bot desactivado para este hilo', { threadId });
  }

  const messages = await prisma.supportMessage.findMany({
    where: { threadId },
    orderBy: { createdAt: 'asc' },
  });

  return {
    threadId: thread.id,
    userId: thread.userId,
    status: thread.status,
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
    data: {
      lastMessageAt: new Date(),
      lastMessagePreview: preview(message),
      unreadByAdmin: false,
      // Si por algún motivo llega una respuesta manual sin haber pasado por
      // getThreadMessagesForAdmin (defensivo), esto también cuenta como
      // "un admin está acá" y apaga el bot para este hilo.
      status: thread.status === 'RESOLVED' ? thread.status : 'ESCALATED',
      adminJoinedAt: thread.adminJoinedAt ?? new Date(),
    },
  });

  const io = getIO();
  if (io) {
    io.to(`user:${thread.userId}`).emit('support_admin_reply', {
      threadId,
      message,
      senderRole: 'ADMIN',
      createdAt: saved.createdAt.toISOString(),
    });
    // Otros admins con el inbox abierto también ven la respuesta reflejada al instante.
    io.to(ADMIN_SUPPORT_ROOM).emit('support_thread_updated', { threadId, lastMessagePreview: preview(message) });
  }

  return { id: saved.id, threadId, message: saved.message, createdAt: saved.createdAt };
}

/** El admin marca el caso como resuelto — recién acá se "cierra" para el
 * cliente. La próxima vez que escriba, sendClientMessage detecta
 * status===RESOLVED y arranca una conversación visualmente nueva (el
 * historial viejo sigue completo en la base, nunca se borra). */
export async function resolveThread(threadId: string) {
  const thread = await prisma.supportThread.findUnique({ where: { id: threadId } });
  if (!thread) throw new BadRequestError('Conversación no encontrada', 'THREAD_NOT_FOUND');

  await prisma.supportThread.update({
    where: { id: threadId },
    data: { status: 'RESOLVED', resolvedAt: new Date(), unreadByAdmin: false },
  });

  const io = getIO();
  if (io) {
    io.to(ADMIN_SUPPORT_ROOM).emit('support_thread_updated', { threadId, resolved: true });
  }

  return { threadId, status: 'RESOLVED' as const };
}

export async function markThreadReadByAdmin(threadId: string) {
  await prisma.supportThread.updateMany({ where: { id: threadId }, data: { unreadByAdmin: false } }).catch((err) => {
    logger.error('[SUPPORT_CHAT] Error marcando hilo como leído', { threadId, err });
  });
}
