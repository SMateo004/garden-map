import { Router, Request, Response } from 'express';
import rateLimit from 'express-rate-limit';
import { authMiddleware } from '../../middleware/auth.middleware.js';
import { asyncHandler } from '../../shared/async-handler.js';
import prisma from '../../config/database.js';
import { getIO } from '../../services/socket.service.js';
import { sendPushToUser, sendPushToAdmins } from '../../services/firebase.service.js';

const REPORT_REASONS = ['HARASSMENT', 'INAPPROPRIATE_CONTENT', 'SPAM', 'SCAM_OR_FRAUD', 'THREATS', 'OTHER'];

const router = Router();

// 60 messages per minute per IP — prevents chat spam / flooding
const chatMessageLimiter = rateLimit({
  windowMs: 60 * 1_000,
  max: 60,
  standardHeaders: true,
  legacyHeaders: false,
  message: { success: false, error: { code: 'RATE_LIMITED', message: 'Demasiados mensajes. Espera un momento.' } },
});

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// GET /api/chat/:bookingId/other-participant - Datos de la otra parte de la conversación
// (necesario para el menú de bloquear/reportar en la pantalla de chat).
router.get('/:bookingId/other-participant', authMiddleware, asyncHandler(async (req: Request, res: Response) => {
    const { bookingId } = req.params;
    if (!UUID_RE.test(bookingId ?? '')) {
        return res.status(400).json({ success: false, error: { message: 'bookingId inválido' } });
    }
    const userId = (req as any).user.userId;

    const booking = await prisma.booking.findFirst({
        where: {
            id: bookingId,
            OR: [
                { clientId: userId },
                { caregiver: { userId } },
            ],
        },
        include: {
            caregiver: { select: { userId: true, user: { select: { firstName: true, lastName: true, profilePicture: true } } } },
            client: { select: { id: true, firstName: true, lastName: true, profilePicture: true } },
        },
    });

    if (!booking) {
        return res.status(403).json({ success: false, error: { message: 'Sin acceso' } });
    }

    const isClient = booking.clientId === userId;
    const other = isClient
        ? { id: booking.caregiver.userId, name: `${booking.caregiver.user.firstName} ${booking.caregiver.user.lastName}`.trim(), photo: booking.caregiver.user.profilePicture ?? null }
        : { id: booking.client.id, name: `${booking.client.firstName} ${booking.client.lastName}`.trim(), photo: booking.client.profilePicture ?? null };

    const blockedByMe = await prisma.userBlock.findFirst({ where: { blockerId: userId, blockedId: other.id } });
    const blockedMe = await prisma.userBlock.findFirst({ where: { blockerId: other.id, blockedId: userId } });

    res.json({
        success: true,
        data: {
            userId: other.id,
            name: other.name,
            photo: other.photo,
            blockedByMe: !!blockedByMe,
            blockedMe: !!blockedMe,
        },
    });
}));

// GET /api/chat/:bookingId/messages - Obtener historial de mensajes
router.get('/:bookingId/messages', authMiddleware, asyncHandler(async (req: Request, res: Response) => {
    const { bookingId } = req.params;
    if (!UUID_RE.test(bookingId ?? '')) {
        return res.status(400).json({ success: false, error: { message: 'bookingId inválido' } });
    }
    const userId = (req as any).user.userId;

    // Verificar acceso al booking
    const booking = await prisma.booking.findFirst({
        where: {
            id: bookingId,
            OR: [
                { clientId: userId },
                { caregiver: { userId } },
            ],
        },
    });

    if (!booking) {
        return res.status(403).json({ success: false, error: { message: 'Sin acceso' } });
    }

    // Traer los ÚLTIMOS 100 (desc + take), no los primeros 100 — con orderBy
    // asc + take:100, una conversación con más de 100 mensajes escondía todo
    // lo posterior al mensaje #100 en cada carga fresca del chat. Se revierte
    // después para mantener el orden cronológico esperado por el cliente.
    const messagesDesc = await prisma.chatMessage.findMany({
        where: { bookingId },
        include: {
            sender: { select: { id: true, firstName: true, lastName: true } },
        },
        orderBy: { createdAt: 'desc' },
        take: 100,
    });
    const messages = messagesDesc.reverse();

    // Marcar como leídos los mensajes del otro usuario
    await prisma.chatMessage.updateMany({
        where: {
            bookingId,
            senderId: { not: userId },
            read: false,
        },
        data: { read: true },
    });

    res.json({
        success: true,
        data: messages.map(m => ({
            id: m.id,
            bookingId: m.bookingId,
            senderId: m.senderId,
            senderName: m.isSystem
                ? 'Sistema'
                : `${(m as any).sender?.firstName ?? ''} ${(m as any).sender?.lastName ?? ''}`.trim(),
            senderRole: m.senderRole,
            message: m.message,
            isSystem: m.isSystem,
            read: m.read,
            createdAt: m.createdAt.toISOString(),
        })),
    });
}));

// POST /api/chat/:bookingId/messages - Enviar un mensaje
router.post('/:bookingId/messages', authMiddleware, chatMessageLimiter, asyncHandler(async (req: Request, res: Response) => {
    const { bookingId } = req.params;
    if (!UUID_RE.test(bookingId ?? '')) {
        return res.status(400).json({ success: false, error: { message: 'bookingId inválido' } });
    }
    const userId = (req as any).user.userId;
    const { message } = req.body;

    if (!message || typeof message !== 'string' || !message.trim()) {
        return res.status(400).json({ success: false, error: { message: 'El mensaje no puede estar vacío' } });
    }
    if (message.length > 2000) {
        return res.status(400).json({ success: false, error: { message: 'El mensaje no puede superar los 2000 caracteres' } });
    }

    // Verificar acceso al booking y obtener roles
    const booking = await prisma.booking.findFirst({
        where: {
            id: bookingId,
            OR: [
                { clientId: userId },
                { caregiver: { userId } },
            ],
        },
        include: {
            caregiver: { select: { userId: true } },
        },
    });

    if (!booking) {
        return res.status(403).json({ success: false, error: { message: 'Sin acceso' } });
    }

    const isClient = booking.clientId === userId;
    const senderRole = isClient ? 'CLIENT' : 'CAREGIVER';
    const recipientId = isClient ? booking.caregiver.userId : booking.clientId;

    // Bloqueo: si cualquiera de las dos partes bloqueó a la otra, no se puede enviar mensajes.
    const blockExists = await prisma.userBlock.findFirst({
        where: {
            OR: [
                { blockerId: userId, blockedId: recipientId },
                { blockerId: recipientId, blockedId: userId },
            ],
        },
    });
    if (blockExists) {
        return res.status(403).json({ success: false, error: { code: 'USER_BLOCKED', message: 'No puedes enviar mensajes a este usuario.' } });
    }

    // Crear el mensaje
    const newMessage = await prisma.chatMessage.create({
        data: {
            bookingId: bookingId!,
            senderId: userId,
            senderRole,
            message: message.trim(),
        },
        include: {
            sender: { select: { id: true, firstName: true, lastName: true } },
        },
    });

    // Si es el PRIMER mensaje del cuidador al cliente → notificación in-app
    if (!isClient) {
        const previousMessages = await prisma.chatMessage.count({
            where: { bookingId, senderRole: 'CAREGIVER' },
        });
        if (previousMessages === 1) {
            // Es el primer mensaje (acabamos de crear el único)
            const senderName = `${(newMessage as any).sender.firstName} ${(newMessage as any).sender.lastName}`;
            await prisma.notification.create({
                data: {
                    userId: recipientId,
                    title: `${senderName} te envió un mensaje 💬`,
                    message: `Tu cuidador se ha puesto en contacto contigo sobre la reserva de ${booking.petName}. Entra al chat para responder.`,
                    type: 'CHAT_MESSAGE',
                },
            });
        }
    }

    const payload = {
        id: newMessage.id,
        bookingId: newMessage.bookingId,
        senderId: newMessage.senderId,
        senderName: `${(newMessage as any).sender.firstName} ${(newMessage as any).sender.lastName}`,
        senderRole: newMessage.senderRole,
        message: newMessage.message,
        read: newMessage.read,
        createdAt: newMessage.createdAt.toISOString(),
    };

    // Broadcast en tiempo real a ambos participantes via Socket.io
    const io = getIO();
    if (io) {
        io.to(`booking:${bookingId}`).emit('new_message', payload);
    }

    // Push notification al destinatario (siempre, no solo el primer mensaje)
    const senderName = payload.senderName;
    sendPushToUser(recipientId, `Mensaje de ${senderName} 💬`, message.trim()).catch(() => {});

    res.status(201).json({ success: true, data: payload });
}));

// GET /api/chat/unread-count - Contar mensajes no leídos
router.get('/unread-count', authMiddleware, asyncHandler(async (req: Request, res: Response) => {
    const userId = (req as any).user.userId;
    const count = await prisma.chatMessage.count({
        where: {
            read: false,
            senderId: { not: userId },
            booking: {
                OR: [
                    { clientId: userId },
                    { caregiver: { userId } },
                ],
            },
        },
    });
    res.json({ success: true, data: { count } });
}));

// GET /api/chat/unread-counts - Desglose por reserva (para mostrar el badge en la lista de reservas)
router.get('/unread-counts', authMiddleware, asyncHandler(async (req: Request, res: Response) => {
    const userId = (req as any).user.userId;
    const unread = await prisma.chatMessage.findMany({
        where: {
            read: false,
            senderId: { not: userId },
            booking: {
                OR: [
                    { clientId: userId },
                    { caregiver: { userId } },
                ],
            },
        },
        select: { bookingId: true },
    });
    const counts: Record<string, number> = {};
    for (const m of unread) {
        counts[m.bookingId] = (counts[m.bookingId] ?? 0) + 1;
    }
    res.json({ success: true, data: { counts } });
}));

// ═══════════════════════════════════════════════════════════════════════════
// BLOQUEO Y REPORTES DE CHAT (App Store 1.2 UGC / Google Play — moderación)
// ═══════════════════════════════════════════════════════════════════════════

// POST /api/chat/block - Bloquear a otro usuario (idempotente)
router.post('/block', authMiddleware, asyncHandler(async (req: Request, res: Response) => {
    const userId = (req as any).user.userId;
    const { userId: targetUserId } = req.body as { userId?: string };

    if (!targetUserId || typeof targetUserId !== 'string' || !UUID_RE.test(targetUserId)) {
        return res.status(400).json({ success: false, error: { message: 'userId inválido' } });
    }
    if (targetUserId === userId) {
        return res.status(400).json({ success: false, error: { message: 'No puedes bloquearte a ti mismo' } });
    }

    await prisma.userBlock.upsert({
        where: { blockerId_blockedId: { blockerId: userId, blockedId: targetUserId } },
        create: { blockerId: userId, blockedId: targetUserId },
        update: {},
    });

    res.json({ success: true, data: { blocked: true } });
}));

// DELETE /api/chat/block/:userId - Desbloquear a un usuario
router.delete('/block/:userId', authMiddleware, asyncHandler(async (req: Request, res: Response) => {
    const userId = (req as any).user.userId;
    const targetUserId = req.params.userId;

    if (!targetUserId || !UUID_RE.test(targetUserId)) {
        return res.status(400).json({ success: false, error: { message: 'userId inválido' } });
    }

    await prisma.userBlock.deleteMany({
        where: { blockerId: userId, blockedId: targetUserId },
    });

    res.json({ success: true, data: { blocked: false } });
}));

// GET /api/chat/blocked-users - Lista de usuarios bloqueados por el usuario actual
router.get('/blocked-users', authMiddleware, asyncHandler(async (req: Request, res: Response) => {
    const userId = (req as any).user.userId;

    const blocks = await prisma.userBlock.findMany({
        where: { blockerId: userId },
        include: {
            blocked: { select: { id: true, firstName: true, lastName: true, profilePicture: true } },
        },
        orderBy: { createdAt: 'desc' },
    });

    res.json({
        success: true,
        data: blocks.map(b => ({
            id: b.blocked.id,
            name: `${b.blocked.firstName} ${b.blocked.lastName}`.trim(),
            photo: b.blocked.profilePicture ?? null,
            blockedAt: b.createdAt.toISOString(),
        })),
    });
}));

// POST /api/chat/report - Reportar a la otra parte de una reserva
router.post('/report', authMiddleware, asyncHandler(async (req: Request, res: Response) => {
    const userId = (req as any).user.userId;
    const { bookingId, reason, details } = req.body as { bookingId?: string; reason?: string; details?: string };

    if (!bookingId || !UUID_RE.test(bookingId)) {
        return res.status(400).json({ success: false, error: { message: 'bookingId inválido' } });
    }
    if (!reason || !REPORT_REASONS.includes(reason)) {
        return res.status(400).json({ success: false, error: { message: 'Motivo de reporte inválido' } });
    }
    if (details !== undefined && (typeof details !== 'string' || details.length > 2000)) {
        return res.status(400).json({ success: false, error: { message: 'Los detalles no pueden superar los 2000 caracteres' } });
    }

    const booking = await prisma.booking.findFirst({
        where: {
            id: bookingId,
            OR: [
                { clientId: userId },
                { caregiver: { userId } },
            ],
        },
        include: {
            caregiver: { select: { userId: true } },
        },
    });

    if (!booking) {
        return res.status(403).json({ success: false, error: { message: 'Sin acceso a esta reserva' } });
    }

    const isClient = booking.clientId === userId;
    const reportedUserId = isClient ? booking.caregiver.userId : booking.clientId;

    // Snapshot de los últimos 20 mensajes como evidencia
    const recentMessages = await prisma.chatMessage.findMany({
        where: { bookingId },
        orderBy: { createdAt: 'desc' },
        take: 20,
        select: { id: true, senderId: true, senderRole: true, message: true, isSystem: true, createdAt: true },
    });

    const report = await prisma.chatReport.create({
        data: {
            bookingId,
            reporterId: userId,
            reportedUserId,
            reason,
            details: details?.trim() || null,
            messagesSnapshot: JSON.stringify(recentMessages.reverse()),
        },
    });

    // Notificar al equipo de Garden — requiere revisión humana.
    await prisma.adminNotification.create({
        data: { type: 'CHAT_REPORT', caregiverId: booking.caregiver.userId, bookingId },
    }).catch(() => {});
    sendPushToAdmins(
        '🚩 Nuevo reporte de chat',
        `Reserva ${bookingId.slice(0, 8).toUpperCase()} — motivo: ${reason}. Revisión requerida.`,
        { type: 'CHAT_REPORT', bookingId }
    ).catch(() => {});

    res.status(201).json({ success: true, data: { id: report.id, status: report.status } });
}));

export default router;
