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

export async function getMyReferral(userId: string) {
  const code = await getOrCreateReferralCode(userId);
  const [referredCount, rewardBS, me] = await Promise.all([
    prisma.user.count({ where: { referredByUserId: userId } }),
    getNumericSetting('referralRewardBS', 20),
    prisma.user.findUnique({ where: { id: userId }, select: { referredByUserId: true } }),
  ]);
  // Solo se puede cargar un código ajeno si todavía no tiene uno propio
  // aplicado Y todavía no completó ningún servicio (anti-abuso retroactivo).
  const completedCount = await prisma.booking.count({ where: { clientId: userId, status: 'COMPLETED' } });
  const canApplyCode = !me?.referredByUserId && completedCount === 0;

  return { code, referredCount, rewardBS, canApplyCode };
}

export async function applyReferralCode(userId: string, code: string) {
  const referrer = await prisma.user.findUnique({ where: { referralCode: code }, select: { id: true } });
  if (!referrer) throw new NotFoundError('Código de invitación no encontrado');
  if (referrer.id === userId) throw new BadRequestError('No podés usar tu propio código', 'CANNOT_REFER_SELF');

  const me = await prisma.user.findUnique({ where: { id: userId }, select: { referredByUserId: true } });
  if (me?.referredByUserId) throw new BadRequestError('Ya aplicaste un código de invitación antes', 'REFERRAL_ALREADY_APPLIED');

  const completedCount = await prisma.booking.count({ where: { clientId: userId, status: 'COMPLETED' } });
  if (completedCount > 0) {
    throw new BadRequestError('Solo se puede cargar un código de invitación antes de tu primer servicio', 'REFERRAL_TOO_LATE');
  }

  await prisma.user.update({ where: { id: userId }, data: { referredByUserId: referrer.id } });
  logger.info('Código de referido aplicado', { userId, referrerId: referrer.id });
  return { applied: true };
}

/** Se llama desde concludeService() al completar un servicio — acredita el
 * bono a ambas partes SOLO en el primer servicio COMPLETED del referido
 * (evita pagar el bono más de una vez, ver referralRewardGiven). No lanza
 * — cualquier error acá no debe tumbar la conclusión real del servicio. */
export async function grantReferralRewardIfEligible(clientId: string): Promise<void> {
  try {
    const client = await prisma.user.findUnique({
      where: { id: clientId },
      select: { referredByUserId: true, referralRewardGiven: true },
    });
    if (!client?.referredByUserId || client.referralRewardGiven) return;

    const completedCount = await prisma.booking.count({ where: { clientId, status: 'COMPLETED' } });
    if (completedCount !== 1) return; // no es el primero — no corresponde el bono

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
