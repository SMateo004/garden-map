/**
 * Cron job que envía recordatorios a clientes y cuidadores antes del inicio del servicio.
 * Se ejecuta cada hora. Envía recordatorio a las 24h y a las 2h antes del servicio.
 * También monitorea hospedajes activos cuya endDate se acerca o ya pasó.
 */
import cron from 'node-cron';
import prisma from '../config/database.js';
import { onServiceReminder } from '../services/notification.service.js';
import { sendPushToUser } from '../services/firebase.service.js';
import logger from '../shared/logger.js';
import { autoPayoutExpiredReviews, calcOvertimeMinutes } from '../modules/booking-service/booking.service.js';

async function procesarRecordatoriosDeServicio() {
  const now = new Date();

  for (const hoursUntil of [24, 2]) {
    const windowStart = new Date(now.getTime() + (hoursUntil - 0.5) * 60 * 60 * 1000);
    const windowEnd = new Date(now.getTime() + (hoursUntil + 0.5) * 60 * 60 * 1000);

    const bookings = await prisma.booking.findMany({
      where: {
        status: 'CONFIRMED',
        OR: [
          { walkDate: { gte: windowStart, lte: windowEnd } },
          { startDate: { gte: windowStart, lte: windowEnd } },
        ],
      },
      select: {
        id: true,
        clientId: true,
        caregiver: { select: { userId: true } },
      },
    });

    if (bookings.length === 0) continue;

    for (const booking of bookings) {
      try {
        await onServiceReminder(booking.id, hoursUntil);

        const pushMsg = `Tu servicio empieza en ${hoursUntil === 24 ? '24 horas' : '2 horas'}. ¡Prepárate!`;
        sendPushToUser(booking.clientId, '⏰ Recordatorio de servicio', pushMsg).catch(() => {});
        if (booking.caregiver?.userId) {
          sendPushToUser(booking.caregiver.userId, '⏰ Recordatorio de servicio', pushMsg).catch(() => {});
        }

        logger.info(`[REMINDERS] Recordatorio ${hoursUntil}h enviado`, { bookingId: booking.id });
      } catch (err: any) {
        logger.error(`[REMINDERS] Error al enviar recordatorio`, { bookingId: booking.id, error: err.message });
      }
    }
  }
}

// ── Aviso de fin de hospedaje ────────────────────────────────────────────────
// Corre cada hora. Avisa al cliente 24h antes y 2h antes de endDate.
// Si endDate ya pasó y el servicio sigue IN_PROGRESS, recuerda al cuidador concluirlo.

async function procesarAvisosFinHospedaje() {
  const now = new Date();

  // 1. Avisos preventivos: 24h y 2h antes del checkout
  for (const hoursUntil of [24, 2]) {
    const windowStart = new Date(now.getTime() + (hoursUntil - 0.5) * 60 * 60 * 1000);
    const windowEnd   = new Date(now.getTime() + (hoursUntil + 0.5) * 60 * 60 * 1000);

    const hospedajes = await prisma.booking.findMany({
      where: {
        status: 'IN_PROGRESS',
        serviceType: 'HOSPEDAJE',
        endDate: { gte: windowStart, lte: windowEnd },
      },
      select: {
        id: true, clientId: true, petName: true, endDate: true,
        caregiver: { select: { userId: true } },
      },
    });

    for (const b of hospedajes) {
      try {
        const label = hoursUntil === 24 ? '24 horas' : '2 horas';
        const title = `🏠 Hospedaje finaliza en ${label}`;
        const msg   = `El hospedaje de ${b.petName ?? 'tu mascota'} termina en ${label}. ¿Necesitas más días?`;

        await prisma.notification.create({
          data: { userId: b.clientId, title, message: msg, type: 'WALK_EXPIRY_WARNING' },
        });
        sendPushToUser(b.clientId, title, msg).catch(() => {});

        if (b.caregiver?.userId) {
          const caregiverTitle = `🏠 Hospedaje termina en ${label}`;
          const caregiverMsg   = `El hospedaje de ${b.petName ?? 'la mascota'} finaliza en ${label}. Prepara el resumen del servicio.`;
          sendPushToUser(b.caregiver.userId, caregiverTitle, caregiverMsg).catch(() => {});
        }

        logger.info(`[HOSPEDAJE-EXPIRY] Aviso ${label} enviado`, { bookingId: b.id });
      } catch (err: any) {
        logger.error('[HOSPEDAJE-EXPIRY] Error en aviso preventivo', { bookingId: b.id, error: err?.message });
      }
    }
  }

  // 2. Aviso de overdue: endDate ya pasó y el servicio no ha sido concluido
  const overdueWindow = new Date(now.getTime() - 2 * 60 * 60 * 1000); // hasta 2h atrás para no spamear
  const overdue = await prisma.booking.findMany({
    where: {
      status: 'IN_PROGRESS',
      serviceType: 'HOSPEDAJE',
      endDate: { lt: now, gte: overdueWindow },
    },
    select: {
      id: true, clientId: true, petName: true,
      caregiver: { select: { userId: true } },
      serviceEvents: true,
    },
  });

  for (const b of overdue) {
    // Solo notificar una vez por booking (evitar spam en cada ciclo)
    const events = (b.serviceEvents as any[]) ?? [];
    const alreadyNotified = events.some((e: any) => e.type === 'HOSPEDAJE_OVERDUE_NOTIFIED');
    if (alreadyNotified) continue;

    try {
      await prisma.booking.update({
        where: { id: b.id },
        data: {
          serviceEvents: [
            ...events,
            { type: 'HOSPEDAJE_OVERDUE_NOTIFIED', timestamp: new Date().toISOString() },
          ],
        },
      });

      const clientTitle = '📋 Hospedaje finalizado — confirma la recepción';
      const clientMsg   = `El período de hospedaje de ${b.petName ?? 'tu mascota'} ha terminado. El cuidador debe concluir el servicio pronto.`;
      await prisma.notification.create({
        data: { userId: b.clientId, title: clientTitle, message: clientMsg, type: 'WALK_EXPIRY_END' },
      });
      sendPushToUser(b.clientId, clientTitle, clientMsg).catch(() => {});

      if (b.caregiver?.userId) {
        const caregiverTitle = '⚠️ Hospedaje vencido — concluye el servicio';
        const caregiverMsg   = `El hospedaje de ${b.petName ?? 'la mascota'} ya terminó. Por favor sube las fotos y concluye el servicio en la app.`;
        await prisma.notification.create({
          data: { userId: b.caregiver.userId, title: caregiverTitle, message: caregiverMsg, type: 'WALK_EXPIRY_END' },
        });
        sendPushToUser(b.caregiver.userId, caregiverTitle, caregiverMsg).catch(() => {});
      }

      logger.info('[HOSPEDAJE-EXPIRY] Aviso overdue enviado', { bookingId: b.id });
    } catch (err: any) {
      logger.error('[HOSPEDAJE-EXPIRY] Error en aviso overdue', { bookingId: b.id, error: err?.message });
    }
  }
}

// ── Recordatorio de calificación post-servicio ───────────────────────────────
// Corre cada hora. Si el servicio lleva ~22-26h completado sin calificación,
// envía un segundo push + email recordando que la calificación libera el pago.

async function procesarRecordatoriosCalificacion() {
  const now = new Date();
  const windowStart = new Date(now.getTime() - 26 * 60 * 60 * 1000);
  const windowEnd   = new Date(now.getTime() - 22 * 60 * 60 * 1000);

  const pendientes = await prisma.booking.findMany({
    where: {
      status: 'COMPLETED',
      ownerRated: false,
      payoutStatus: 'PENDING',
      serviceEndedAt: { gte: windowStart, lte: windowEnd },
    },
    select: {
      id: true,
      clientId: true,
      petName: true,
      serviceType: true,
      caregiver: { select: { user: { select: { firstName: true, lastName: true } } } },
    },
  });

  for (const b of pendientes) {
    try {
      const caregiverName = [b.caregiver?.user?.firstName, b.caregiver?.user?.lastName].filter(Boolean).join(' ') || 'tu cuidador';
      const svcLabel = b.serviceType === 'PASEO' ? 'paseo' : b.serviceType === 'GUARDERIA' ? 'guardería' : 'hospedaje';

      await prisma.notification.create({
        data: {
          userId: b.clientId,
          title: '⭐ ¡No olvides calificar!',
          message: `Aún no has calificado el ${svcLabel} de ${b.petName ?? 'tu mascota'} con ${caregiverName}. Tu calificación libera el pago al cuidador.`,
          type: 'SERVICE_COMPLETED',
        },
      });
      sendPushToUser(
        b.clientId,
        '⭐ ¡Califica el servicio!',
        `Recuerda calificar el ${svcLabel} de ${b.petName ?? 'tu mascota'}. El cuidador espera su pago.`
      ).catch(() => {});

      logger.info('[RATING-REMINDER] Recordatorio 24h enviado', { bookingId: b.id });
    } catch (err: any) {
      logger.error('[RATING-REMINDER] Error', { bookingId: b.id, err: err?.message });
    }
  }
}

// ── Recordatorio de fin de servicio sin marcar (ningún lado lo cerró) ────────
// Corre cada hora. Cubre los 3 tipos de servicio (paseo, guardería, hospedaje):
// si ya pasó el horario acordado + los 15 min de gracia y nadie (ni cuidador
// concluyendo, ni dueño marcando fin) cerró el servicio, insiste con push a
// ambos hasta que uno de los dos actúe. Throttle de 30 min via lastEndReminderAt
// para no reenviar en cada corrida del cron.
const REMINDER_THROTTLE_MS = 30 * 60 * 1000;

async function procesarRecordatoriosFinServicioSinMarcar() {
  const now = new Date();

  const enCurso = await prisma.booking.findMany({
    where: { status: 'IN_PROGRESS', clientMarkedEndAt: null },
    select: {
      id: true, clientId: true, petName: true, serviceType: true,
      serviceStartedAt: true, duration: true, endDate: true,
      lastEndReminderAt: true,
      caregiver: { select: { userId: true } },
    },
  });

  for (const b of enCurso) {
    try {
      const overtimeMins = calcOvertimeMinutes(b.serviceType, b.serviceStartedAt, b.duration, b.endDate, now);
      if (overtimeMins <= 0) continue; // aún dentro del horario + gracia

      if (b.lastEndReminderAt && now.getTime() - b.lastEndReminderAt.getTime() < REMINDER_THROTTLE_MS) {
        continue; // ya se envió un recordatorio reciente
      }

      await prisma.booking.update({ where: { id: b.id }, data: { lastEndReminderAt: now } });

      const svcLabel = b.serviceType === 'PASEO' ? 'paseo' : b.serviceType === 'GUARDERIA' ? 'guardería' : 'hospedaje';

      const clientTitle = '⏰ ¿Ya terminó el servicio?';
      const clientMsg = `El ${svcLabel} de ${b.petName ?? 'tu mascota'} ya pasó su horario acordado. Si ya terminó, márcalo en la app para evitar cargos de tiempo extra.`;
      await prisma.notification.create({
        data: { userId: b.clientId, title: clientTitle, message: clientMsg, type: 'SYSTEM' },
      });
      sendPushToUser(b.clientId, clientTitle, clientMsg).catch(() => {});

      if (b.caregiver?.userId) {
        const caregiverTitle = '⏰ Cierra el servicio';
        const caregiverMsg = `El ${svcLabel} de ${b.petName ?? 'la mascota'} ya pasó su horario acordado. Sube tus fotos y concluye el servicio para cobrar.`;
        await prisma.notification.create({
          data: { userId: b.caregiver.userId, title: caregiverTitle, message: caregiverMsg, type: 'SYSTEM' },
        });
        sendPushToUser(b.caregiver.userId, caregiverTitle, caregiverMsg).catch(() => {});
      }

      logger.info('[END-REMINDER] Recordatorio enviado', { bookingId: b.id, overtimeMins });
    } catch (err: any) {
      logger.error('[END-REMINDER] Error', { bookingId: b.id, error: err?.message });
    }
  }
}

// ── Procesador de notificaciones masivas programadas ─────────────────────────
// Corre cada minuto. Si hay MassNotifications con scheduledAt <= now y status SCHEDULED, las envía.

const BATCH_SIZE = 200;

async function procesarNotificacionesMasivasProgramadas() {
  const now = new Date();
  // También recupera envíos que quedaron en SENDING (reinicio del servidor a mitad de proceso)
  const pendientes = await prisma.massNotification.findMany({
    where: {
      OR: [
        { status: 'SCHEDULED', scheduledAt: { lte: now } },
        { status: 'SENDING' }, // retomar envíos interrumpidos
      ],
    },
    select: { id: true, title: true, message: true, targetType: true, targetZone: true, sentCount: true },
  });

  for (const n of pendientes) {
    try {
      await prisma.massNotification.update({ where: { id: n.id }, data: { status: 'SENDING' } });

      const where: any = { isDeleted: { not: true } };
      if (n.targetType === 'clients') where.role = 'CLIENT';
      else if (n.targetType === 'caregivers') where.role = 'CAREGIVER';
      else if (n.targetType === 'zone' && n.targetZone) {
        where.OR = [
          { caregiverProfile: { zone: n.targetZone } },
          { clientProfile: { addressZone: n.targetZone } },
        ];
      }

      let sentCount = n.sentCount; // retoma desde donde quedó si fue interrumpido
      let failCount = 0;
      let cursor: string | undefined;

      while (true) {
        const users = await prisma.user.findMany({
          where,
          select: { id: true },
          take: BATCH_SIZE,
          ...(cursor ? { skip: 1, cursor: { id: cursor } } : {}),
          orderBy: { id: 'asc' },
        });
        if (users.length === 0) break;
        cursor = users[users.length - 1]!.id;

        try {
          await prisma.notification.createMany({
            data: users.map(u => ({ userId: u.id, title: n.title, message: n.message, type: 'SYSTEM' })),
            skipDuplicates: true,
          });
          sentCount += users.length;
          users.forEach(u => sendPushToUser(u.id, n.title, n.message).catch(() => {}));
        } catch { failCount += users.length; }

        if (users.length < BATCH_SIZE) break;
      }

      await prisma.massNotification.update({
        where: { id: n.id },
        data: { status: 'SENT', sentAt: new Date(), sentCount, failCount },
      });
      logger.info('[MASS-NOTIF] Enviada', { id: n.id, sentCount });
    } catch (err) {
      await prisma.massNotification.update({ where: { id: n.id }, data: { status: 'FAILED' } });
      logger.error('[MASS-NOTIF] Error', { id: n.id, err });
    }
  }
}

export function iniciarJobServiceReminders() {
  // Notificaciones masivas programadas — cada minuto
  cron.schedule('* * * * *', () => {
    procesarNotificacionesMasivasProgramadas().catch(err =>
      logger.error('[MASS-NOTIF] Job falló', { err })
    );
  });

  // Recordatorios de inicio de servicio + avisos de fin de hospedaje + recordatorios de calificación
  cron.schedule('0 * * * *', async () => {
    await procesarRecordatoriosDeServicio();
    await procesarAvisosFinHospedaje().catch(err =>
      logger.error('[HOSPEDAJE-EXPIRY] Job falló', { err })
    );
    await procesarRecordatoriosCalificacion().catch(err =>
      logger.error('[RATING-REMINDER] Job falló', { err })
    );
    await procesarRecordatoriosFinServicioSinMarcar().catch(err =>
      logger.error('[END-REMINDER] Job falló', { err })
    );
  });

  // Auto-payout: cada 4 horas libera pagos de servicios completados hace +48h sin calificar
  cron.schedule('0 */4 * * *', async () => {
    try {
      const count = await autoPayoutExpiredReviews();
      if (count > 0) logger.info(`[AutoPayout] ${count} desembolsos automáticos procesados`);
    } catch (err) {
      logger.error('[AutoPayout] Error en job de auto-payout', { err });
    }
  });

  logger.info('[REMINDERS] Job de recordatorios de servicio activo (incluye avisos fin de hospedaje + recordatorios de calificación).');
}
