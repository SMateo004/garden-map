import { randomBytes } from 'node:crypto';
import prisma from '../../config/database.js';
import { BadRequestError, NotFoundError } from '../../shared/errors.js';
import { getNumericSetting } from '../../utils/settings-cache.js';
import { sendPushToUser } from '../../services/firebase.service.js';
import logger from '../../shared/logger.js';

const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // sin 0/O/1/I — se confunden a mano

function generateCode(length = 6): string {
  const bytes = randomBytes(length);
  let code = '';
  for (let i = 0; i < length; i++) code += CODE_ALPHABET[bytes[i]! % CODE_ALPHABET.length];
  return code;
}

/** Genera (o devuelve el ya existente) código de referido del usuario —
 * perezoso a propósito: nunca se toca el registro, que ya tiene 4 flujos
 * distintos (cliente/cuidador/profesional/empresa) y es sensible. */
async function getOrCreateReferralCode(userId: string): Promise<string> {
  const user = await prisma.user.findUnique({ where: { id: userId }, select: { referralCode: true } });
  if (user?.referralCode) return user.referralCode;

  // Reintenta ante colisión (muy improbable con 6 chars de un alfabeto de
  // 33 símbolos — ~1.2 mil millones de combinaciones), nunca falla por eso.
  for (let attempt = 0; attempt < 5; attempt++) {
    const code = generateCode();
    try {
      await prisma.user.update({ where: { id: userId }, data: { referralCode: code } });
      return code;
    } catch (e: any) {
      if (e?.code === 'P2002') continue; // unique constraint — colisión, reintentar
      throw e;
    }
  }
  throw new Error('No se pudo generar un código de referido único');
}

/** Servicios terminados de la persona, como dueño o como cuidador: el código solo vale antes del primero. */
async function completedServicesOf(userId: string): Promise<number> {
  const [asClient, asCaregiver] = await Promise.all([
    prisma.booking.count({ where: { clientId: userId, status: 'COMPLETED' } }),
    prisma.booking.count({ where: { status: 'COMPLETED', caregiver: { userId } } }),
  ]);
  return asClient + asCaregiver;
}

/**
 * ¿El servicio que dispara el bono es legítimo para pagarlo? Se cobró de verdad, no lo armó un admin,
 * y no es entre el que invitó y su invitado (ni entre dos invitados del mismo): si no, alguien podía
 * invitarse a sí mismo con una segunda cuenta, reservarse y cobrar los dos bonos.
 */
async function qualifyingBooking(bookingId: string | undefined, referrerId: string): Promise<boolean> {
  if (!bookingId) return false;
  const b = await prisma.booking.findUnique({
    where: { id: bookingId },
    select: {
      paidAt: true, createdByAdmin: true, clientId: true,
      client: { select: { referredByUserId: true } },
      caregiver: { select: { userId: true, user: { select: { referredByUserId: true } } } },
    },
  });
  if (!b || !b.paidAt || b.createdByAdmin) return false;
  const parties = [b.clientId, b.caregiver.userId];
  const partiesReferredBy = [b.client?.referredByUserId, b.caregiver.user?.referredByUserId];
  if (parties.includes(referrerId)) return false;
  // Dueño y cuidador invitados por la misma persona: el bono saldría de un servicio entre conocidos.
  if (partiesReferredBy[0] && partiesReferredBy[0] === partiesReferredBy[1]) return false;
  return true;
}

export async function getMyReferral(userId: string) {
  const code = await getOrCreateReferralCode(userId);
  const [referredCount, rewardedCount, rewardBS, caregiverRewardBS, me] = await Promise.all([
    prisma.user.count({ where: { referredByUserId: userId } }),
    // Invitados que ya completaron su primer servicio (bono pagado a ambos).
    prisma.user.count({ where: { referredByUserId: userId, referralRewardGiven: true } }),
    getNumericSetting('referralRewardBS', 20),
    getNumericSetting('referralCaregiverRewardBS', 30),
    prisma.user.findUnique({ where: { id: userId }, select: { referredByUserId: true, referralRewardGiven: true } }),
  ]);
  // Solo se puede cargar un código ajeno si todavía no tiene uno propio
  // aplicado Y todavía no completó ningún servicio (anti-abuso retroactivo).
  const completedCount = await completedServicesOf(userId);
  const canApplyCode = !me?.referredByUserId && completedCount === 0;
  // Si a este usuario lo invitaron: si su propio bono está pendiente o ya se pagó.
  const myBonus = !me?.referredByUserId ? 'NONE' : me.referralRewardGiven ? 'REWARDED' : 'PENDING';

  return { code, referredCount, rewardedCount, rewardBS, caregiverRewardBS, canApplyCode, myBonus };
}

export async function applyReferralCode(userId: string, code: string) {
  const referrer = await prisma.user.findUnique({ where: { referralCode: code }, select: { id: true } });
  if (!referrer) throw new NotFoundError('Código de invitación no encontrado');
  if (referrer.id === userId) throw new BadRequestError('No puedes usar tu propio código', 'CANNOT_REFER_SELF');

  const me = await prisma.user.findUnique({ where: { id: userId }, select: { referredByUserId: true } });
  if (me?.referredByUserId) throw new BadRequestError('Ya aplicaste un código de invitación antes', 'REFERRAL_ALREADY_APPLIED');

  const completedCount = await completedServicesOf(userId);
  if (completedCount > 0) {
    throw new BadRequestError('Solo se puede cargar un código de invitación antes de tu primer servicio', 'REFERRAL_TOO_LATE');
  }

  // FIX (auditoría 2026-10-01, referidos): claim atómico — sin esto, dos
  // códigos de referido distintos aplicados casi simultáneamente por el
  // mismo usuario podían pasar ambos el chequeo de arriba (ninguno había
  // comiteado todavía) y el que escribiera último "ganaba" en silencio, sin
  // error para el primero. No rompe dinero (el bono se acredita después, con
  // su propio claim atómico en grantReferralRewardIfEligible), pero sí podía
  // asignarle al usuario un referente distinto del que realmente quiso usar.
  const claimed = await prisma.user.updateMany({
    where: { id: userId, referredByUserId: null },
    data: { referredByUserId: referrer.id },
  });
  if (claimed.count === 0) {
    throw new BadRequestError('Ya aplicaste un código de invitación antes', 'REFERRAL_ALREADY_APPLIED');
  }
  logger.info('Código de referido aplicado', { userId, referrerId: referrer.id });
  return { applied: true };
}

/** Se llama desde concludeService() al completar un servicio — acredita el
 * bono a ambas partes SOLO en el primer servicio COMPLETED del referido
 * (evita pagar el bono más de una vez, ver referralRewardGiven). No lanza
 * — cualquier error acá no debe tumbar la conclusión real del servicio. */
export async function grantReferralRewardIfEligible(clientId: string, bookingId?: string): Promise<void> {
  try {
    const client = await prisma.user.findUnique({
      where: { id: clientId },
      select: { referredByUserId: true, referralRewardGiven: true },
    });
    if (!client?.referredByUserId || client.referralRewardGiven) return;

    const completedCount = await prisma.booking.count({ where: { clientId, status: 'COMPLETED' } });
    if (completedCount !== 1) return; // no es el primero — no corresponde el bono
    if (!(await qualifyingBooking(bookingId, client.referredByUserId))) return;

    const rewardBS = await getNumericSetting('referralRewardBS', 20);
    if (rewardBS <= 0) return;

    await prisma.$transaction(async (tx) => {
      // Atomic claim — evita doble bono si concludeService corriera dos
      // veces casi en simultáneo para el mismo cliente (no debería, pero
      // el mismo criterio de seguridad que el resto de este archivo).
      const claimed = await tx.user.updateMany({
        where: { id: clientId, referralRewardGiven: false },
        data: { referralRewardGiven: true },
      });
      if (claimed.count === 0) return;

      const referrerId = client.referredByUserId!;
      const updatedReferred = await tx.user.update({
        where: { id: clientId },
        data: { balance: { increment: rewardBS } },
        select: { balance: true },
      });
      await tx.walletTransaction.create({
        data: {
          userId: clientId, type: 'REFERRAL_BONUS', amount: rewardBS,
          balance: Number(updatedReferred.balance),
          description: 'Bono por tu primer servicio con un código de invitación',
          status: 'COMPLETED',
        },
      });

      const updatedReferrer = await tx.user.update({
        where: { id: referrerId },
        data: { balance: { increment: rewardBS } },
        select: { balance: true },
      });
      await tx.walletTransaction.create({
        data: {
          userId: referrerId, type: 'REFERRAL_BONUS', amount: rewardBS,
          balance: Number(updatedReferrer.balance),
          description: 'Bono por invitar a un amigo que completó su primer servicio',
          status: 'COMPLETED',
        },
      });

      sendPushToUser(
        referrerId,
        '💚 Ganaste un bono por invitar',
        `La persona que invitaste completó su primer servicio — recibiste Bs ${rewardBS.toFixed(2)}.`,
        { type: 'REFERRAL_BONUS' }
      ).catch(() => {});
    });

    logger.info('Bono de referido acreditado', { clientId, rewardBS });
  } catch (e: any) {
    logger.error('Error acreditando bono de referido (no bloquea la conclusión del servicio)', { clientId, error: e?.message });
  }
}

/**
 * Referidos del lado del cuidador (oferta): si a un cuidador lo invitó alguien con su código,
 * cuando termina su PRIMER servicio como cuidador los dos ganan `referralCaregiverRewardBS`
 * (Bs 30 por defecto). Un mismo usuario cobra un solo bono de referido en total, como dueño o
 * como cuidador (mismo flag referralRewardGiven). Se llama desde concludeService. No lanza.
 */
export async function grantCaregiverReferralRewardIfEligible(caregiverProfileId: string, bookingId?: string): Promise<void> {
  try {
    const profile = await prisma.caregiverProfile.findUnique({ where: { id: caregiverProfileId }, select: { userId: true } });
    if (!profile) return;
    const caregiverUserId = profile.userId;
    const user = await prisma.user.findUnique({
      where: { id: caregiverUserId },
      select: { referredByUserId: true, referralRewardGiven: true },
    });
    if (!user?.referredByUserId || user.referralRewardGiven) return;

    const completedCount = await prisma.booking.count({ where: { caregiverId: caregiverProfileId, status: 'COMPLETED' } });
    if (completedCount !== 1) return;
    if (!(await qualifyingBooking(bookingId, user.referredByUserId))) return;

    const rewardBS = await getNumericSetting('referralCaregiverRewardBS', 30);
    if (rewardBS <= 0) return;
    const referrerId = user.referredByUserId;

    await prisma.$transaction(async (tx) => {
      const claimed = await tx.user.updateMany({
        where: { id: caregiverUserId, referralRewardGiven: false },
        data: { referralRewardGiven: true },
      });
      if (claimed.count === 0) return;

      for (const [uid, description] of [
        [caregiverUserId, 'Bono por tu primer servicio como cuidador con un código de invitación'],
        [referrerId, 'Bono por invitar a un cuidador que completó su primer servicio'],
      ] as const) {
        await tx.$queryRaw`SELECT id FROM "users" WHERE id = ${uid} FOR UPDATE`;
        const updated = await tx.user.update({
          where: { id: uid },
          data: { balance: { increment: rewardBS } },
          select: { balance: true },
        });
        await tx.walletTransaction.create({
          data: {
            userId: uid, type: 'REFERRAL_BONUS', amount: rewardBS,
            balance: Number(updated.balance), description, status: 'COMPLETED',
          },
        });
      }
    });

    sendPushToUser(
      referrerId,
      '💚 Ganaste un bono por invitar',
      `El cuidador que invitaste completó su primer servicio — recibiste Bs ${rewardBS.toFixed(2)}.`,
      { type: 'REFERRAL_BONUS' }
    ).catch(() => {});
    logger.info('Bono de referido de cuidador acreditado', { caregiverProfileId, rewardBS });
  } catch (e: any) {
    logger.error('Error acreditando bono de referido de cuidador (no bloquea la conclusión)', { caregiverProfileId, error: e?.message });
  }
}
