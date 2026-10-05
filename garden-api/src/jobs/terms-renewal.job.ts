/**
 * Job diario: recuerda a los cuidadores que deben volver a aceptar los Términos (cada 2 meses o por
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
import { computeTermsStatus } from '../modules/legal/caregiver-terms.service.js';

const NOTIFICATION_TYPE = 'TERMS_RENEWAL';
const REPEAT_EVERY_DAYS = 3;

export function iniciarJobRenovacionTerminos() {
  cron.schedule('30 10 * * *', async () => {
    await enviarRecordatoriosTerminos();
  });
  logger.info('[TERMS-RENEWAL JOB] Recordatorio diario de renovación de Términos activo.');
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
    select: { id: true, userId: true, termsAcceptedAt: true },
  });

  const repeatCutoff = new Date(now.getTime() - REPEAT_EVERY_DAYS * 24 * 60 * 60 * 1000);
  let sent = 0;

  for (const c of caregivers) {
    try {
      const content = buildTermsNotification(computeTermsStatus(c.termsAcceptedAt, now));
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
