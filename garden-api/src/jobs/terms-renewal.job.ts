/**
 * Job diario (09:30 Bolivia y un repaso tras cada arranque): recuerda a los cuidadores que deben volver a aceptar los Términos (cada 2 meses o por
 * versión nueva) — HAYAN o no prestado servicios. Ver caregiver-terms.service.ts.
 *
 * Recorre todos los cuidadores aprobados y no suspendidos. Si falta poco para el vencimiento
 * (<= 7 días) o ya venció / hay una versión nueva, deja una notificación in-app + push. Se repite cada
 * 3 días mientras siga pendiente (no a diario, para no saturar); no respeta la preferencia de
 * recordatorios porque es un aviso legal que condiciona su visibilidad.
 */
import cron from 'node-cron';
import prisma from '../config/database.js';
import logger from '../shared/logger.js';
import { sendPushToUser } from '../services/firebase.service.js';
import { computeTermsStatus, isTermsExemptEmail } from '../modules/legal/caregiver-terms.service.js';

const NOTIFICATION_TYPE = 'TERMS_RENEWAL';
const REPEAT_EVERY_DAYS = 3;

/** Tras arrancar, se espera un poco para que la API termine de calentar antes del repaso. */
const STARTUP_DELAY_MS = 90_000;
/** Bolivia = UTC-4 todo el año. Los avisos solo salen de día para no despertar a nadie con un push. */
const BOLIVIA_UTC_OFFSET_H = -4;
const NOTIFY_FROM_HOUR = 8;
const NOTIFY_UNTIL_HOUR = 21;

export function esHoraDeAvisar(now: Date = new Date()): boolean {
  const hour = (now.getUTCHours() + BOLIVIA_UTC_OFFSET_H + 24) % 24;
  return hour >= NOTIFY_FROM_HOUR && hour < NOTIFY_UNTIL_HOUR;
}

export function iniciarJobRenovacionTerminos() {
  // 13:30 UTC = 09:30 en Bolivia.
  cron.schedule('30 13 * * *', async () => {
    await enviarRecordatoriosTerminos();
  });

  // El cron solo dispara si el servidor está despierto justo a esa hora: con un plan que se duerme por
  // inactividad (o con un reinicio por cada despliegue) puede no ocurrir nunca. Este repaso al arrancar lo
  // cubre. Es seguro repetirlo: no vuelve a avisar dentro de REPEAT_EVERY_DAYS ni de noche.
  const startup = setTimeout(() => {
    if (!esHoraDeAvisar()) return;
    enviarRecordatoriosTerminos().catch((err) => logger.error('[TERMS-RENEWAL JOB] repaso de arranque falló', { err }));
  }, STARTUP_DELAY_MS);
  startup.unref?.();

  logger.info('[TERMS-RENEWAL JOB] Recordatorio de renovación de Términos activo (diario 09:30 Bolivia + repaso al arrancar).');
}

export function buildTermsNotification(status: ReturnType<typeof computeTermsStatus>): { title: string; message: string } | null {
  if (status.reason === 'EXPIRED' || status.reason === 'NEVER') {
    return {
      title: 'Acepta los Términos para volver a recibir reservas',
      message: 'Tu aceptación de los Términos de Garden venció, por eso tu perfil está oculto y no recibe reservas nuevas. Acéptalos en la app y vuelves a aparecer al instante.',
    };
  }
  if (status.reason === 'NEW_VERSION') {
    return {
      title: 'Actualizamos los Términos de Garden',
      message: 'Hay una versión nueva de los Términos y del Contrato de Cuidador. Léela y acéptala en la app para que tu perfil siga visible.',
    };
  }
  if (status.reminderDue && status.daysLeft !== null) {
    return {
      title: 'Renueva tu aceptación de los Términos',
      message: `Tu aceptación vence en ${status.daysLeft} ${status.daysLeft === 1 ? 'día' : 'días'}. Se renueva cada 2 meses: acéptala en la app para que tu perfil siga visible.`,
    };
  }
  return null;
}

export async function enviarRecordatoriosTerminos(now: Date = new Date()): Promise<number> {
  const caregivers = await prisma.caregiverProfile.findMany({
    where: { status: 'APPROVED', suspended: false },
    select: { id: true, userId: true, termsAcceptedAt: true, user: { select: { email: true } } },
  });

  const repeatCutoff = new Date(now.getTime() - REPEAT_EVERY_DAYS * 24 * 60 * 60 * 1000);
  let sent = 0;

  for (const c of caregivers) {
    try {
      // Las cuentas de prueba de las tiendas (reviewer.*) están exentas: nunca se les avisa.
      const content = buildTermsNotification(computeTermsStatus(c.termsAcceptedAt, now, { exempt: isTermsExemptEmail(c.user?.email) }));
      if (!content) continue;

      const recent = await prisma.notification.findFirst({
        where: { userId: c.userId, type: NOTIFICATION_TYPE, createdAt: { gte: repeatCutoff } },
        select: { id: true },
      });
      if (recent) continue;

      await prisma.notification.create({ data: { userId: c.userId, title: content.title, message: content.message, type: NOTIFICATION_TYPE } });
      sendPushToUser(c.userId, content.title, content.message).catch((err) =>
        logger.error('[TERMS-RENEWAL JOB] push falló', { userId: c.userId, err }),
      );
      sent++;
    } catch (err) {
      logger.error('[TERMS-RENEWAL JOB] Error avisando a cuidador', { caregiverId: c.id, err });
    }
  }

  if (sent > 0) logger.info(`[TERMS-RENEWAL JOB] ${sent} aviso(s) de renovación enviados`);
  return sent;
}
