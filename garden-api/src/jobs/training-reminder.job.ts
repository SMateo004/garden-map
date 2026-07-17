/**
 * Job diario que recuerda a los cuidadores amateur (0 años de experiencia)
 * sus capacitaciones AMATEUR obligatorias pendientes — mientras no las
 * completen no aparecen en el marketplace (ver training.service.ts,
 * CaregiverProfile.trainingComplete).
 *
 * Notificación in-app + push: se reenvía cada día que siga pendiente.
 * Correo: solo la primera vez (trainingReminderEmailSentAt).
 */

import cron from 'node-cron';
import prisma from '../config/database.js';
import logger from '../shared/logger.js';
import { onTrainingReminder } from '../services/notification.service.js';
import { TrainingAudience } from '@prisma/client';

export function iniciarJobRecordatorioCapacitaciones() {
  cron.schedule('0 10 * * *', async () => {
    await enviarRecordatoriosCapacitaciones();
  });
  logger.info('[TRAINING-REMINDER JOB] Recordatorio diario de capacitaciones activo.');
}

export async function enviarRecordatoriosCapacitaciones() {
  const pendientes = await prisma.caregiverProfile.findMany({
    where: { isAmateur: true, status: 'APPROVED', trainingComplete: false },
    select: { id: true, userId: true, servicesOffered: true, trainingReminderEmailSentAt: true },
  });

  if (pendientes.length === 0) return;

  for (const c of pendientes) {
    try {
      const mandatoryTopics = await prisma.trainingTopic.findMany({
        where: { audience: TrainingAudience.AMATEUR, isActive: true, service: { in: c.servicesOffered } },
        select: { id: true, title: true },
      });
      if (mandatoryTopics.length === 0) continue;

      const progress = await prisma.caregiverTrainingProgress.findMany({
        where: { caregiverId: c.id, topicId: { in: mandatoryTopics.map((t) => t.id) } },
        select: { topicId: true, completedAt: true, exemptedByAdmin: true },
      });
      const doneIds = new Set(progress.filter((p) => p.exemptedByAdmin || p.completedAt !== null).map((p) => p.topicId));
      const pendingTitles = mandatoryTopics.filter((t) => !doneIds.has(t.id)).map((t) => t.title);
      if (pendingTitles.length === 0) continue; // trainingComplete quedó desactualizado, se recalculará solo en el próximo cambio

      const sendEmail = c.trainingReminderEmailSentAt === null;
      await onTrainingReminder(c.userId, pendingTitles, sendEmail);
      if (sendEmail) {
        await prisma.caregiverProfile.update({
          where: { id: c.id },
          data: { trainingReminderEmailSentAt: new Date() },
        });
      }
    } catch (err) {
      logger.error('[TRAINING-REMINDER JOB] Error recordando a cuidador', { caregiverId: c.id, err });
    }
  }

  logger.info(`[TRAINING-REMINDER JOB] Recordatorios enviados a ${pendientes.length} cuidadores.`);
}
