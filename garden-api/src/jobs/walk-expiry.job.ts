/**
 * Job que corre cada minuto y revisa paseos IN_PROGRESS próximos a vencer.
 * - 5 min antes del fin: notifica al cliente que recoja a su mascota o amplíe.
 * - Al vencer: notifica al cliente que el tiempo terminó y puede ampliar.
 * Usa serviceEvents para no duplicar notificaciones.
 */
import cron from 'node-cron';
import prisma from '../config/database.js';
import { sendPushToUser } from '../services/firebase.service.js';
import logger from '../shared/logger.js';

export function iniciarJobWalkExpiry() {
    cron.schedule('* * * * *', async () => {
        await procesarVencimientoPaseos();
    });
    logger.info('[WALK-EXPIRY JOB] Monitor de vencimiento de paseos activo.');
}

export async function procesarVencimientoPaseos() {
    try {
        const now = new Date();
        const nowMins = now.getHours() * 60 + now.getMinutes();

        // Solo paseos IN_PROGRESS con hora de inicio conocida
        const activos = await prisma.booking.findMany({
            where: {
                status: 'IN_PROGRESS',
                serviceType: 'PASEO',
                startTime: { not: null },
                duration: { not: null },
            },
            select: {
                id: true,
                clientId: true,
                petName: true,
                startTime: true,
                duration: true,
                serviceEvents: true,
                serviceStartedAt: true,
            },
        });

        for (const booking of activos) {
            try {
                // Calcular fin basado en serviceStartedAt real (más preciso que startTime)
                let endTime: Date;
                if (booking.serviceStartedAt) {
                    endTime = new Date(booking.serviceStartedAt.getTime() + (booking.duration! * 60 * 1000));
                } else {
                    // Fallback: calcular desde startTime del día actual
                    const parts = (booking.startTime ?? '00:00').split(':');
                    const startMins = parseInt(parts[0] ?? '0') * 60 + parseInt(parts[1] ?? '0');
                    const endMins = startMins + booking.duration!;
                    const endDate = new Date(now);
                    endDate.setHours(Math.floor(endMins / 60), endMins % 60, 0, 0);
                    endTime = endDate;
                }

                const msToEnd = endTime.getTime() - now.getTime();
                const minsToEnd = Math.round(msToEnd / 60000);

                const events = (booking.serviceEvents as any[]) ?? [];
                const alreadyNotified5 = events.some(e => e.type === 'EXPIRY_WARNING_5MIN');
                const alreadyNotifiedEnd = events.some(e => e.type === 'EXPIRY_WARNING_END');

                // Notificación 5 min antes
                if (minsToEnd <= 5 && minsToEnd > 0 && !alreadyNotified5) {
                    await prisma.booking.update({
                        where: { id: booking.id },
                        data: {
                            serviceEvents: [
                                ...events,
                                { type: 'EXPIRY_WARNING_5MIN', timestamp: new Date().toISOString() },
                            ],
                        },
                    });

                    await prisma.notification.create({
                        data: {
                            userId: booking.clientId,
                            title: '⏱️ ¡Quedan 5 minutos!',
                            message: `El paseo de ${booking.petName ?? 'tu mascota'} termina en 5 min. ¿Todo bien? Puedes ampliar el tiempo desde la app.`,
                            type: 'WALK_EXPIRY_WARNING',
                        },
                    });

                    sendPushToUser(
                        booking.clientId,
                        '⏱️ ¡Quedan 5 minutos!',
                        `El paseo de ${booking.petName ?? 'tu mascota'} termina pronto. ¿Amplías el tiempo?`
                    ).catch(() => {});

                    logger.info('[WALK-EXPIRY] 5-min warning sent', { bookingId: booking.id });
                }

                // Notificación al vencer
                if (minsToEnd <= 0 && !alreadyNotifiedEnd) {
                    await prisma.booking.update({
                        where: { id: booking.id },
                        data: {
                            serviceEvents: [
                                ...events.filter(e => e.type !== 'EXPIRY_WARNING_5MIN'),
                                { type: 'EXPIRY_WARNING_5MIN', timestamp: events.find(e => e.type === 'EXPIRY_WARNING_5MIN')?.timestamp ?? new Date().toISOString() },
                                { type: 'EXPIRY_WARNING_END', timestamp: new Date().toISOString() },
                            ],
                        },
                    });

                    await prisma.notification.create({
                        data: {
                            userId: booking.clientId,
                            title: '🐾 Tu mascota está lista',
                            message: `El tiempo del paseo de ${booking.petName ?? 'tu mascota'} ha terminado. ¿Deseas añadir más tiempo?`,
                            type: 'WALK_EXPIRY_END',
                        },
                    });

                    sendPushToUser(
                        booking.clientId,
                        '🐾 Tu mascota está lista',
                        `El paseo de ${booking.petName ?? 'tu mascota'} terminó. ¿Amplías el tiempo?`
                    ).catch(() => {});

                    logger.info('[WALK-EXPIRY] End warning sent', { bookingId: booking.id });
                }
            } catch (err) {
                logger.error('[WALK-EXPIRY] Error processing booking', { bookingId: booking.id, err });
            }
        }
    } catch (err) {
        logger.error('[WALK-EXPIRY] Job failed', { err });
    }
}
