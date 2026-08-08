import prisma from '../../config/database.js';
import { CaregiverStatus } from '@prisma/client';
import { NotFoundError } from '../../shared/errors.js';
import { sendPushToUser } from '../../services/firebase.service.js';
import { getAvailabilityCalendar } from '../booking-service/booking.service.js';
import logger from '../../shared/logger.js';

export async function joinWaitlist(clientId: string, caregiverId: string) {
  const caregiver = await prisma.caregiverProfile.findFirst({
    where: { id: caregiverId, status: CaregiverStatus.APPROVED, suspended: false },
    select: { id: true },
  });
  if (!caregiver) throw new NotFoundError('Cuidador no encontrado o no disponible');

  return prisma.caregiverWaitlist.upsert({
    where: { clientId_caregiverId: { clientId, caregiverId } },
    create: { clientId, caregiverId },
    // Si ya estaba en la lista, no hace nada (mantiene lastNotifiedAt tal
    // cual — volver a apretar "Avisame" no debe resetear el cooldown de
    // spam ni reenviar antes de tiempo).
    update: {},
  });
}

export async function leaveWaitlist(clientId: string, caregiverId: string) {
  await prisma.caregiverWaitlist.deleteMany({ where: { clientId, caregiverId } });
  return { removed: true };
}

export async function getWaitlistStatus(clientId: string, caregiverId: string) {
  const entry = await prisma.caregiverWaitlist.findUnique({
    where: { clientId_caregiverId: { clientId, caregiverId } },
    select: { id: true },
  });
  return { onWaitlist: !!entry };
}

const RENOTIFY_COOLDOWN_DAYS = 3;

/** Job: revisa cada entrada de lista de espera y avisa si el cuidador ya
 * tiene cupo — reusa getAvailabilityCalendar() (mismo chequeo real que el
 * calendario visible en el perfil), nunca inventa un criterio propio de
 * "disponible". No lanza — un error acá no debe tumbar el resto del job. */
export async function checkWaitlistsAndNotify(): Promise<{ notified: number }> {
  const cooldownCutoff = new Date(Date.now() - RENOTIFY_COOLDOWN_DAYS * 24 * 60 * 60 * 1000);
  const entries = await prisma.caregiverWaitlist.findMany({
    where: { OR: [{ lastNotifiedAt: null }, { lastNotifiedAt: { lt: cooldownCutoff } }] },
    select: {
      id: true, clientId: true, caregiverId: true,
      caregiver: { select: { user: { select: { firstName: true } } } },
    },
  });

  // Agrupa por caregiverId para no recalcular el calendario una vez por
  // cliente en lista de espera del mismo cuidador.
  const calendarCache = new Map<string, boolean>();
  let notified = 0;

  for (const entry of entries) {
    try {
      let hasOpening = calendarCache.get(entry.caregiverId);
      if (hasOpening === undefined) {
        const calendar = await getAvailabilityCalendar(entry.caregiverId, 7);
        hasOpening = calendar.some((d) => d.available);
        calendarCache.set(entry.caregiverId, hasOpening);
      }
      if (!hasOpening) continue;

      const caregiverName = entry.caregiver.user.firstName ?? 'Tu cuidador favorito';
      await sendPushToUser(
        entry.clientId,
        `🎉 ${caregiverName} ya tiene cupo`,
        'Tiene disponibilidad esta semana — reservá antes de que se llene de nuevo.',
        { type: 'WAITLIST_OPENING', caregiverId: entry.caregiverId }
      ).catch(() => {});
      await prisma.caregiverWaitlist.update({ where: { id: entry.id }, data: { lastNotifiedAt: new Date() } });
      notified++;
    } catch (e: any) {
      logger.error('[WAITLIST] Error procesando entrada', { entryId: entry.id, error: e?.message });
    }
  }

  if (notified > 0) logger.info('[WAITLIST] Avisos enviados', { notified, total: entries.length });
  return { notified };
}
