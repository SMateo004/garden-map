/**
 * Cron job que envía recordatorios a clientes y cuidadores antes del inicio del servicio.
 * Se ejecuta cada 15 min. Envía recordatorio a las 24h, a las 2h y a los 30 min antes del
 * servicio (ventana ±10 min alrededor de cada umbral, con guard de idempotencia por booking).
 * También monitorea hospedajes activos cuya endDate se acerca o ya pasó.
 */
import cron from 'node-cron';
import prisma from '../config/database.js';
import { onServiceReminder } from '../services/notification.service.js';
import { sendPushToUser } from '../services/firebase.service.js';
import logger from '../shared/logger.js';
import { autoPayoutExpiredReviews, calcOvertimeMinutes } from '../modules/booking-service/booking.service.js';

// Ventana alrededor de cada umbral (24h / 2h). Corre cada 15 min (ver
// cron abajo) con una ventana de ±10 min: da precisión real ("el momento
// preciso" que pide el usuario, en vez de la vieja ±30min/hora que dejaba
// el aviso caer en cualquier punto entre 23.5h y 24.5h antes) y además dos
// corridas consecutivas se solapan un poco (10 min de margen contra un tick
// de cron saltado), lo cual ahora es seguro gracias al guard de
// idempotencia de abajo (antes esta función no tenía ninguno — a
// diferencia de todos los demás recordatorios de este archivo).
const REMINDER_WINDOW_MARGIN_MS = 10 * 60 * 1000;

// Token legible sin puntos decimales, usado tanto para el texto del push
// como para el tipo de evento guardado en el ledger `serviceEvents`
// (ej. "30 minutos" / "SERVICE_REMINDER_30MIN_SENT" en vez de "0.5 horas" /
// "SERVICE_REMINDER_0.5H_SENT").
function reminderLabel(hoursUntil: number): string {
  return hoursUntil < 1 ? `${Math.round(hoursUntil * 60)} minutos` : `${hoursUntil} horas`;
}
function reminderEventToken(hoursUntil: number): string {
  return hoursUntil < 1 ? `${Math.round(hoursUntil * 60)}MIN` : `${hoursUntil}H`;
}

async function procesarRecordatoriosDeServicio() {
  const now = new Date();

  for (const hoursUntil of [24, 2, 0.5]) {
    const windowStart = new Date(now.getTime() + hoursUntil * 60 * 60 * 1000 - REMINDER_WINDOW_MARGIN_MS);
    const windowEnd = new Date(now.getTime() + hoursUntil * 60 * 60 * 1000 + REMINDER_WINDOW_MARGIN_MS);
    const eventType = `SERVICE_REMINDER_${reminderEventToken(hoursUntil)}_SENT`;

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
        petName: true,
        startTime: true,
        serviceEvents: true,
        caregiver: { select: { userId: true } },
      },
    });

    if (bookings.length === 0) continue;

    for (const booking of bookings) {
      try {
        // Idempotencia: cada (booking, umbral) solo se notifica una vez, sin
        // importar cuántas veces el cron vuelva a escanear la ventana (server
        // restart, tick perdido y recuperado, ventanas solapadas, etc.). Mismo
        // patrón de ledger en `serviceEvents` que ya usa el aviso de
        // hospedaje-vencido más abajo.
        const events = (booking.serviceEvents as any[]) ?? [];
        const alreadyNotified = events.some((e: any) => e.type === eventType);
        if (alreadyNotified) continue;

        await prisma.booking.update({
          where: { id: booking.id },
          data: {
            serviceEvents: [...events, { type: eventType, timestamp: new Date().toISOString() }],
          },
        });

        await onServiceReminder(booking.id, hoursUntil);

        // Incluye mascota y hora para que dos recordatorios de bookings
        // distintos no se lean como "la misma notificación repetida".
        const timeLabel = booking.startTime ? ` (${booking.startTime})` : '';
        const pushMsg = `El servicio de ${booking.petName ?? 'tu mascota'}${timeLabel} empieza en ${reminderLabel(hoursUntil)}. ¡Prepárate!`;
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
// Corre cada 15 min (ventana ±10min por umbral). Avisa al cliente 24h antes y 2h antes de endDate.
// Si endDate ya pasó y el servicio sigue IN_PROGRESS, recuerda al cuidador concluirlo.

async function procesarAvisosFinHospedaje() {
  const now = new Date();

  // 1. Avisos preventivos: 24h y 2h antes del checkout
  for (const hoursUntil of [24, 2]) {
    const windowStart = new Date(now.getTime() + hoursUntil * 60 * 60 * 1000 - REMINDER_WINDOW_MARGIN_MS);
    const windowEnd   = new Date(now.getTime() + hoursUntil * 60 * 60 * 1000 + REMINDER_WINDOW_MARGIN_MS);
    const eventType = `HOSPEDAJE_EXPIRY_${hoursUntil}H_SENT`;

    const hospedajes = await prisma.booking.findMany({
      where: {
        status: 'IN_PROGRESS',
        serviceType: 'HOSPEDAJE',
        endDate: { gte: windowStart, lte: windowEnd },
      },
      select: {
        id: true, clientId: true, petName: true, endDate: true, serviceEvents: true,
        caregiver: { select: { userId: true } },
      },
    });

    for (const b of hospedajes) {
      // Mismo guard de idempotencia que el resto de esta ventana: evita
      // reenviar el mismo aviso si el cron vuelve a escanear la ventana.
      const events = (b.serviceEvents as any[]) ?? [];
      if (events.some((e: any) => e.type === eventType)) continue;

      try {
        await prisma.booking.update({
          where: { id: b.id },
          data: { serviceEvents: [...events, { type: eventType, timestamp: new Date().toISOString() }] },
        });

        const label = hoursUntil === 24 ? '24 horas' : '2 horas';
        // Checkout exacto (día + hora), no solo "en 24 horas" — dos hospedajes
        // que vencen el mismo día ya no se leen como el mismo aviso genérico.
        // b.endDate viene filtrado por el where (gte/lte) así que siempre existe en
        // este punto — el fallback a `now` es solo para satisfacer el tipo nullable de Prisma.
        const effectiveEndDate = b.endDate ?? now;
        const checkoutDay  = effectiveEndDate.toLocaleDateString('es-BO', { day: 'numeric', month: 'short' });
        const checkoutTime = effectiveEndDate.toLocaleTimeString('es-BO', { hour: '2-digit', minute: '2-digit' });
        const title = `🏠 Hospedaje de ${b.petName ?? 'tu mascota'} finaliza en ${label}`;
        const msg   = `El hospedaje de ${b.petName ?? 'tu mascota'} termina el ${checkoutDay} a las ${checkoutTime}. ¿Necesitas sumar más días?`;

        await prisma.notification.create({
          data: { userId: b.clientId, title, message: msg, type: 'WALK_EXPIRY_WARNING' },
        });
        sendPushToUser(b.clientId, title, msg).catch(() => {});

        if (b.caregiver?.userId) {
          const caregiverTitle = `🏠 Checkout de ${b.petName ?? 'la mascota'} en ${label}`;
          const caregiverMsg   = `El hospedaje de ${b.petName ?? 'la mascota'} termina el ${checkoutDay} a las ${checkoutTime}. Ten listas las fotos y el resumen del servicio.`;
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
      id: true, clientId: true, petName: true, endDate: true,
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

      // Cuánto tiempo pasó desde el checkout acordado — da peso real al aviso
      // en vez del genérico "ya terminó" (que se siente igual sea 1h o 2h tarde).
      const overdueMs = b.endDate ? now.getTime() - b.endDate.getTime() : 0;
      const overdueLabel = overdueMs >= 60 * 60 * 1000
        ? `${Math.floor(overdueMs / (60 * 60 * 1000))}h`
        : `${Math.max(1, Math.round(overdueMs / 60000))} min`;

      const clientTitle = '📋 Hospedaje finalizado — confirma la recepción';
      const clientMsg   = `El hospedaje de ${b.petName ?? 'tu mascota'} terminó hace ${overdueLabel}. Tu cuidador debe concluirlo pronto para liberar tu pago.`;
      await prisma.notification.create({
        data: { userId: b.clientId, title: clientTitle, message: clientMsg, type: 'WALK_EXPIRY_END' },
      });
      sendPushToUser(b.clientId, clientTitle, clientMsg).catch(() => {});

      if (b.caregiver?.userId) {
        const caregiverTitle = '⚠️ Hospedaje vencido — concluye ya';
        const caregiverMsg   = `El hospedaje de ${b.petName ?? 'la mascota'} terminó hace ${overdueLabel}. Sube las fotos finales y concluye el servicio para cobrar.`;
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
// Corre cada 15 min. Si el servicio lleva ~22-26h completado sin calificación,
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
      // Sin esto, cada corrida horaria dentro de la ventana de 4h reenviaba el
      // mismo recordatorio (hasta 4 veces) al mismo dueño para el mismo booking.
      ratingReminderSentAt: null,
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
        `${caregiverName} cuidó a ${b.petName ?? 'tu mascota'} en su ${svcLabel}. Calificalo para liberar su pago.`
      ).catch(() => {});

      await prisma.booking.update({ where: { id: b.id }, data: { ratingReminderSentAt: new Date() } });

      logger.info('[RATING-REMINDER] Recordatorio 24h enviado', { bookingId: b.id });
    } catch (err: any) {
      logger.error('[RATING-REMINDER] Error', { bookingId: b.id, err: err?.message });
    }
  }
}

// ── Recordatorio de fin de servicio sin marcar (ningún lado lo cerró) ────────
// Corre cada 15 min. Cubre los 3 tipos de servicio (paseo, guardería, hospedaje):
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
      lastEndReminderAt: true, pausedAt: true, totalPausedMinutes: true,
      caregiver: { select: { userId: true } },
    },
  });

  for (const b of enCurso) {
    try {
      // No molestar a nadie con "¿ya terminó?" mientras hay una emergencia
      // activa sin resolver — el tiempo está congelado a propósito.
      if (b.pausedAt) continue;
      const overtimeMins = calcOvertimeMinutes(b.serviceType, b.serviceStartedAt, b.duration, b.endDate, now, b.totalPausedMinutes);
      if (overtimeMins <= 0) continue; // aún dentro del horario + gracia

      if (b.lastEndReminderAt && now.getTime() - b.lastEndReminderAt.getTime() < REMINDER_THROTTLE_MS) {
        continue; // ya se envió un recordatorio reciente
      }

      await prisma.booking.update({ where: { id: b.id }, data: { lastEndReminderAt: now } });

      const svcLabel = b.serviceType === 'PASEO' ? 'paseo' : b.serviceType === 'GUARDERIA' ? 'guardería' : 'hospedaje';
      // El minutaje real de atraso (ya calculado arriba) hace que el aviso escale
      // con la situación real, en vez de sonar igual a los 5 min que a las 2 horas.
      const overtimeLabel = overtimeMins >= 60
        ? `${(overtimeMins / 60).toFixed(1)}h`
        : `${overtimeMins} min`;

      const clientTitle = '⏰ ¿Ya terminó el servicio?';
      const clientMsg = `El ${svcLabel} de ${b.petName ?? 'tu mascota'} lleva ${overtimeLabel} de más sobre el horario acordado. Si ya terminó, márcalo en la app para evitar cargos de tiempo extra.`;
      await prisma.notification.create({
        data: { userId: b.clientId, title: clientTitle, message: clientMsg, type: 'SYSTEM' },
      });
      sendPushToUser(b.clientId, clientTitle, clientMsg).catch(() => {});

      if (b.caregiver?.userId) {
        const caregiverTitle = '⏰ Cierra el servicio';
        const caregiverMsg = `El ${svcLabel} de ${b.petName ?? 'la mascota'} lleva ${overtimeLabel} fuera de horario. Sube tus fotos y concluye para cobrar el tiempo extra.`;
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
    select: { id: true, title: true, message: true, targetType: true, targetZone: true, sentCount: true, status: true },
  });

  for (const n of pendientes) {
    try {
      // Guard atómico: si dos corridas del cron (solapadas, o una interrumpida
      // que otra retoma) ven la misma fila antes de que cualquiera la marque
      // SENDING, esto asegura que solo una la "reclame" — la otra recibe
      // count === 0 y no reenvía el broadcast completo a toda la audiencia
      // por segunda vez. Mismo patrón que scheduled-notifications.job.ts.
      const claimed = await prisma.massNotification.updateMany({
        where: { id: n.id, status: n.status },
        data: { status: 'SENDING' },
      });
      if (claimed.count === 0) continue; // otra corrida ya la está procesando

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
  // Corre cada 15 min (antes cada hora) para que los recordatorios de "24h antes" /
  // "2h antes" caigan cerca del momento preciso (ventana ±10min, ver
  // REMINDER_WINDOW_MARGIN_MS) en vez de en cualquier punto de una ventana de
  // ±30min chequeada una sola vez por hora. Ahora es seguro correrlo más seguido
  // porque cada función de este bloque tiene guard de idempotencia (ver
  // serviceEvents / ratingReminderSentAt / lastEndReminderAt).
  cron.schedule('*/15 * * * *', async () => {
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
