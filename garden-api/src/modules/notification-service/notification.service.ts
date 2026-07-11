import prisma from '../../config/database.js';
import { NotFoundError } from '../../shared/errors.js';

export async function getMyNotifications(userId: string) {
    return prisma.notification.findMany({
        where: { userId },
        orderBy: { createdAt: 'desc' },
        take: 50,
    });
}

export async function markAsRead(notificationId: string, userId: string) {
    // prisma.update lanza P2025 (Record not found) si el id no existe o no es
    // de este usuario, y sin este chequeo eso llegaba al cliente como 500 sin
    // manejar en vez de un 404 claro.
    const existing = await prisma.notification.findFirst({
        where: { id: notificationId, userId },
        select: { id: true },
    });
    if (!existing) throw new NotFoundError('Notificación no encontrada');
    return prisma.notification.update({
        where: { id: notificationId },
        data: { read: true, readAt: new Date() },
    });
}

export async function markAllAsRead(userId: string) {
    return prisma.notification.updateMany({
        where: { userId, read: false },
        data: { read: true, readAt: new Date() },
    });
}

export async function getUnreadCount(userId: string) {
    return prisma.notification.count({
        where: { userId, read: false },
    });
}
