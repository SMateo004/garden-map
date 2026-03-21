import { Router, Request, Response } from 'express';
import { authMiddleware } from '../../middleware/auth.middleware.js';
import { asyncHandler } from '../../shared/async-handler.js';
import prisma from '../../config/database.js';

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
            senderName: `${m.sender.firstName} ${m.sender.lastName}`,
            senderRole: m.senderRole,
            message: m.message,
            read: m.read,
            createdAt: m.createdAt.toISOString(),
        })),
    });
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
