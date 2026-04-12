import { Router, Request, Response } from 'express';
import { authMiddleware } from '../../middleware/auth.middleware.js';
import { asyncHandler } from '../../shared/async-handler.js';
import prisma from '../../config/database.js';
import { getIO } from '../../services/socket.service.js';

const router = Router();

// GET /api/chat/:bookingId/messages - Obtener historial de mensajes
router.get('/:bookingId/messages', authMiddleware, asyncHandler(async (req: Request, res: Response) => {
    const { bookingId } = req.params;
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

    const messages = await prisma.chatMessage.findMany({
        where: { bookingId },
        include: {
            sender: { select: { id: true, firstName: true, lastName: true } },
        },
        orderBy: { createdAt: 'asc' },
        take: 100,
    });

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
            senderName: `${(m as any).sender.firstName} ${(m as any).sender.lastName}`,
            senderRole: m.senderRole,
            message: m.message,
            read: m.read,
            createdAt: m.createdAt.toISOString(),
        })),
    });
}));

// POST /api/chat/:bookingId/messages - Enviar un mensaje
router.post('/:bookingId/messages', authMiddleware, asyncHandler(async (req: Request, res: Response) => {
    const { bookingId } = req.params;
    const userId = (req as any).user.userId;
    const { message } = req.body;

    if (!message || typeof message !== 'string' || !message.trim()) {
        return res.status(400).json({ success: false, error: { message: 'El mensaje no puede estar vacío' } });
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

export default router;
