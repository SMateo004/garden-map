/**
 * Job que corre cada minuto y revisa paseos Y guarderías IN_PROGRESS próximos a vencer.
 * - 5 min antes del fin: notifica al cliente que recoja a su mascota.
 * - Al vencer: notifica al cliente que el tiempo terminó.
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

        // Paseos Y guarderías IN_PROGRESS con duración conocida
        const activos = await prisma.booking.findMany({
            where: {
                status: 'IN_PROGRESS',
                serviceType: { in: ['PASEO', 'GUARDERIA'] },
                duration: { not: null },
            },
            select: {
                id: true,
                clientId: true,
                petName: true,
                serviceType: true,
                walkDate: true,
                startTime: true,
                duration: true,
                serviceEvents: true,
                serviceStartedAt: true,
                pausedAt: true,
            },
        });

        for (const booking of activos) {
            try {
                // No avisar "se acaba tu tiempo" mientras hay una emergencia activa
                // sin resolver — el reloj está congelado a propósito.
                if (booking.pausedAt) continue;
                // Calcular fin basado en serviceStartedAt real (más preciso que startTime)
                let endTime: Date;
                if (booking.serviceStartedAt) {
                    endTime = new Date(booking.serviceStartedAt.getTime() + (booking.duration! * 60 * 1000));
                } else if (booking.walkDate && booking.startTime) {
                    // Fallback: usar la fecha real del paseo (walkDate) + startTime, no la fecha de hoy
                    const parts = (booking.startTime ?? '00:00').split(':');
                    const startMins = parseInt(parts[0] ?? '0') * 60 + parseInt(parts[1] ?? '0');
                    const endMins = startMins + booking.duration!;
                    const walkDateBase = new Date(booking.walkDate);
                    walkDateBase.setHours(Math.floor(endMins / 60), endMins % 60, 0, 0);
                    endTime = walkDateBase;
                } else {
                    // Sin información suficiente: asumir que el paseo vence en 24h desde ahora (no notificar)
                    endTime = new Date(now.getTime() + 24 * 60 * 60 * 1000);
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

                    const isGuarderia = (booking as any).serviceType === 'GUARDERIA';
                    const serviceLabel = isGuarderia ? 'guardería' : 'paseo';
                    await prisma.notification.create({
                        data: {
                            userId: booking.clientId,
                            title: '⏱️ ¡Quedan 5 minutos!',
                            message: `La ${serviceLabel} de ${booking.petName ?? 'tu mascota'} termina en 5 min. Ve a recoger a tu mascota.`,
                            type: 'WALK_EXPIRY_WARNING',
                        },
                    });

                    sendPushToUser(
                        booking.clientId,
                        '⏱️ ¡Quedan 5 minutos!',
                        `La ${serviceLabel} de ${booking.petName ?? 'tu mascota'} termina pronto. ¡Ve a buscarla!`
                    ).catch(() => {});

                    logger.info('[WALK-EXPIRY] 5-min warning sent', { bookingId: booking.id });
                }

                // Notificación al vencer
                if (minsToEnd <= 0 && !alreadyNotifiedEnd) {
                    // Append-only: simply add the END event to existing events (don't filter/re-add 5MIN)
                    await prisma.booking.update({
                        where: { id: booking.id },
                        data: {
                            serviceEvents: [
                                ...events,
                                { type: 'EXPIRY_WARNING_END', timestamp: new Date().toISOString() },
                            ],
                        },
                    });

                    const isGuarderiaEnd = (booking as any).serviceType === 'GUARDERIA';
                    const serviceLabelEnd = isGuarderiaEnd ? 'guardería' : 'paseo';
                    await prisma.notification.create({
                        data: {
                            userId: booking.clientId,
                            title: '🐾 Tu mascota está lista',
                            message: `El tiempo de la ${serviceLabelEnd} de ${booking.petName ?? 'tu mascota'} ha terminado. ¡Es hora de recogerla!`,
                            type: 'WALK_EXPIRY_END',
                        },
                    });

                    sendPushToUser(
                        booking.clientId,
                        '🐾 Tu mascota está lista',
                        `La ${serviceLabelEnd} de ${booking.petName ?? 'tu mascota'} terminó.`
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
