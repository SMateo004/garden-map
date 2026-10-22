/**
 * Recordatorio a cuidadores que empezaron el registro y no lo terminaron.
 *
 * El embudo del cuidador (Admin > Analítica) mostró que la mayoría se queda en el primer paso
 * — registrados sin verificar identidad ni enviar el perfil — y nadie se lo recordaba. Este job
 * les avisa qué les falta, con un toque que abre directo su registro: a los 1, 3 y 7 días de
 * registrarse (máx. 3 avisos). Solo a registros de las últimas 2 semanas: no se reactiva de golpe
 * a quien se fue hace meses (esos aparecen en "Se quedaron a mitad de camino" para contactarlos).
 */
import prisma from '../config/database.js';
import logger from '../shared/logger.js';
import { sendPushToUser } from '../services/firebase.service.js';
import { scheduleExclusive } from './job-lease.js';

const WAVES_DAYS = [1, 3, 7];
const DAY = 24 * 60 * 60 * 1000;

export function iniciarJobCaregiverOnboardingNudge() {
  // 10:00 en Bolivia.
  scheduleExclusive('caregiver-onboarding-nudge', '0 14 * * *', async () => {
    await enviarRecordatoriosRegistroCuidador().catch((err) =>
      logger.error('[ONBOARDING-NUDGE] falló', { err: (err as Error)?.message }));
  });
  logger.info('[ONBOARDING-NUDGE JOB] Recordatorio de registro de cuidador activo.');
}

export async function enviarRecordatoriosRegistroCuidador(now = new Date()): Promise<number> {
  const candidates = await prisma.caregiverProfile.findMany({
    where: {
      status: 'DRAFT',
      profileStatus: 'INCOMPLETE',
      suspended: false,
      onboardingNudgeCount: { lt: WAVES_DAYS.length },
      createdAt: { gte: new Date(now.getTime() - 14 * DAY) },
      user: { isDeleted: false, NOT: { email: { startsWith: 'reviewer.' } } },
    },
    select: { id: true, userId: true, createdAt: true, onboardingNudgeCount: true, identityVerificationStatus: true },
  });

  let sent = 0;
  for (const cg of candidates) {
    const waveDay = WAVES_DAYS[cg.onboardingNudgeCount]!;
    if (now.getTime() - cg.createdAt.getTime() < waveDay * DAY) continue;

    const identityDone = cg.identityVerificationStatus === 'VERIFIED';
    const title = identityDone ? 'Te falta poco para recibir reservas' : 'Termina tu registro en GARDEN';
    const message = identityDone
      ? 'Ya verificaste tu identidad. Completa tu perfil (fotos, precios y horarios) para aparecer en el marketplace.'
      : 'Te falta verificar tu identidad: solo tu carnet y una selfie, son 2 minutos. Después completas tu perfil y empiezas a recibir reservas.';

    // Reclamo atómico: dos corridas no mandan el mismo aviso dos veces.
    const claimed = await prisma.caregiverProfile.updateMany({
      where: { id: cg.id, onboardingNudgeCount: cg.onboardingNudgeCount },
      data: { onboardingNudgeCount: { increment: 1 }, onboardingNudgeAt: now },
    });
    if (claimed.count === 0) continue;

    await prisma.notification.create({ data: { userId: cg.userId, title, message, type: 'CAREGIVER_ONBOARDING' } });
    sendPushToUser(cg.userId, title, message, { type: 'CAREGIVER_ONBOARDING' }).catch(() => {});
    sent++;
  }
  if (sent > 0) logger.info(`[ONBOARDING-NUDGE] ${sent} recordatorio(s) de registro enviados`);
  return sent;
}
