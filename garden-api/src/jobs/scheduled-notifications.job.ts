/**
 * Job que cada minuto revisa las notificaciones programadas y las envía cuando llega su hora.
 */
import cron from 'node-cron';
import prisma from '../config/database.js';
import { sendPush } from '../services/firebase.service.js';
import logger from '../shared/logger.js';

export function iniciarJobNotificacionesProgramadas() {
    // Cada minuto
    cron.schedule('* * * * *', async () => {
        await procesarNotificacionesProgramadas();
    });
    logger.info('[NOTIF JOB] Scheduler de notificaciones programadas activo.');
}

export async function procesarNotificacionesProgramadas() {
    const pendientes = await prisma.adminBroadcastNotification.findMany({
        where: {
            status: 'SCHEDULED',
            scheduledAt: { lte: new Date() },
        },
    });

    if (pendientes.length === 0) return;

    for (const notif of pendientes) {
        try {
            // Guard contra race condition: solo procesar si sigue SCHEDULED. Un
            // `update` plano por id no protegía contra dos corridas del cron
            // solapadas (p.ej. si el envío a muchos usuarios tarda más de 1 min,
            // el próximo tick podía recoger la misma notificación "SCHEDULED" y
            // reenviarla por completo a todos los usuarios). Con `updateMany`
            // condicionado al estado previo, la segunda corrida obtiene count=0
            // y no reprocesa — mismo patrón que el resto de jobs de expiración.
            const claimed = await prisma.adminBroadcastNotification.updateMany({
                where: { id: notif.id, status: 'SCHEDULED' },
                data: { status: 'SENT', sentAt: new Date() },
            });
            if (claimed.count === 0) continue; // otra corrida ya la está procesando/procesó

            let whereRole: object = {};
            if (notif.target === 'CUIDADORES') whereRole = { role: 'CAREGIVER' };
            else if (notif.target === 'DUENOS') whereRole = { role: 'CLIENT' };

            const users = await prisma.user.findMany({
                where: { ...whereRole, isDeleted: false },
                select: { id: true, fcmToken: true },
            });

            // Crear notificaciones en DB
            await prisma.notification.createMany({
                data: users.map(u => ({
                    userId: u.id,
                    title: notif.title,
                    message: notif.message,
                    type: notif.type,
                    read: false,
                })),
            });

            // Push FCM best-effort
            const pushPromises = users
                .filter(u => !!u.fcmToken)
                .map(u => sendPush(u.fcmToken!, notif.title, notif.message));
            await Promise.allSettled(pushPromises);

            // Actualizar sentCount
            await prisma.adminBroadcastNotification.update({
                where: { id: notif.id },
                data: { sentCount: users.length },
            });

            logger.info(`[NOTIF JOB] Notificación "${notif.title}" enviada a ${users.length} usuarios (${notif.target})`);
        } catch (err) {
            logger.error(`[NOTIF JOB] Error procesando notificación ${notif.id}:`, err);
            // Revertir para reintentar
            await prisma.adminBroadcastNotification.update({
                where: { id: notif.id },
                data: { status: 'SCHEDULED' },
            }).catch(() => {});
        }
    }
}
