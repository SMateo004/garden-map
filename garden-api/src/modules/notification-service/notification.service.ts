import prisma from '../../config/database.js';

export async function getMyNotifications(userId: string) {
    return prisma.notification.findMany({
        where: { userId },
        orderBy: { createdAt: 'desc' },
        take: 50,
    });
}

export async function markAsRead(notificationId: string, userId: string) {
    return prisma.notification.update({
        where: { id: notificationId, userId },
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
