/**
 * Propinas "por cobrar".
 *
 * El dueño puede dejar propina aunque no le alcance el saldo: se le descuenta
 * igual de User.balance (puede quedar negativo = deuda, que se cobra con su
 * próximo pago, ver debtRecoveryAmount en initPayment/payment.service.ts).
 * Al cuidador le llega al instante solo lo que el saldo cubría; el resto queda
 * como WalletTransaction TIP_RECEIVED en estado PENDING (no suma en
 * User.balance ni en "Ganado") y se libera cuando el dueño salda su deuda.
 *
 * Retenerla evita que un dueño falso deje propina sin plata, el cuidador la
 * retire y GARDEN pierda ese dinero si el dueño nunca vuelve a pagar.
 *
 * Orden de cobro: la deuda del dueño se considera saldada primero por lo que
 * NO es propina (tiempo extra, pagos no recibidos); las propinas pendientes se
 * liberan, de la más vieja a la más nueva, cuando lo que queda de deuda ya no
 * las alcanza. Una propina no se libera en partes.
 */
import { Prisma } from '@prisma/client';
import prisma from '../../config/database.js';
import logger from '../../shared/logger.js';
import { sendPushToUser } from '../../services/firebase.service.js';
import { emitWalletUpdated } from '../../services/socket.service.js';

export const TIP_PENDING_DESCRIPTION = 'Propina por cobrar';

/**
 * Libera las propinas pendientes del dueño [clientId] que su saldo actual ya
 * cubre. Llamar dentro de una transacción; bloquea la fila del dueño y la de
 * cada cuidador al que le acredita. Devuelve cuántos Bs liberó.
 */
export async function releasePendingTips(tx: Prisma.TransactionClient, clientId: string): Promise<number> {
  await tx.$queryRaw`SELECT id FROM "users" WHERE id = ${clientId} FOR UPDATE`;
  const client = await tx.user.findUnique({ where: { id: clientId }, select: { balance: true } });
  const debt = Math.max(0, -Number(client?.balance ?? 0));

  const tipped = await tx.booking.findMany({
    where: { clientId, tipAmount: { not: null } },
    select: { id: true },
  });
  if (tipped.length === 0) return 0;
  const pending = await tx.walletTransaction.findMany({
    where: { type: 'TIP_RECEIVED', status: 'PENDING', bookingId: { in: tipped.map((b) => b.id) } },
    orderBy: { createdAt: 'asc' },
  });
  if (pending.length === 0) return 0;

  const totalPending = pending.reduce((s, t) => s + Number(t.amount), 0);
  // Lo que de la deuda actual corresponde a propinas todavía sin pagar.
  let releasable = Math.max(0, totalPending - debt);
  let released = 0;
  const credited: { userId: string; amount: number; bookingId: string | null }[] = [];

  for (const tip of pending) {
    const amount = Number(tip.amount);
    if (amount > releasable + 0.001) break; // FIFO: no saltar a una más chica
    // Primero se reclama la fila (condicional): si otra liberación concurrente
    // ya la tomó, no se acredita dos veces.
    const claimed = await tx.walletTransaction.updateMany({
      where: { id: tip.id, status: 'PENDING' },
      data: {
        status: 'COMPLETED',
        description: `Propina recibida — reserva ${(tip.bookingId ?? '').slice(0, 8)} (cobrada al dueño)`,
      },
    });
    if (claimed.count === 0) continue;
    await tx.$queryRaw`SELECT id FROM "users" WHERE id = ${tip.userId} FOR UPDATE`;
    const caregiver = await tx.user.update({
      where: { id: tip.userId },
      data: { balance: { increment: amount } },
      select: { balance: true },
    });
    await tx.walletTransaction.update({ where: { id: tip.id }, data: { balance: Number(caregiver.balance) } });
    releasable -= amount;
    released += amount;
    credited.push({ userId: tip.userId, amount, bookingId: tip.bookingId });
  }

  for (const c of credited) {
    sendPushToUser(
      c.userId,
      '💚 Ya tienes tu propina',
      `Se liberó la propina de Bs ${c.amount.toFixed(2)} que te dejaron — ya está en tu billetera.`,
      { type: 'TIP_RECEIVED', ...(c.bookingId ? { bookingId: c.bookingId } : {}) }
    ).catch(() => {});
    emitWalletUpdated(c.userId);
  }
  if (released > 0) logger.info('Propinas por cobrar liberadas', { clientId, released, count: credited.length });
  return released;
}

/** Barrido periódico: libera lo que ya se pueda para cada dueño con propinas pendientes
 * (cubre cualquier forma en que el dueño haya saldado su deuda: pago, reembolso, ajuste). */
export async function releaseAllPendingTips(): Promise<number> {
  const pending = await prisma.walletTransaction.findMany({
    where: { type: 'TIP_RECEIVED', status: 'PENDING', bookingId: { not: null } },
    select: { bookingId: true },
  });
  if (pending.length === 0) return 0;
  const bookings = await prisma.booking.findMany({
    where: { id: { in: pending.map((p) => p.bookingId!) } },
    select: { clientId: true },
  });
  let total = 0;
  for (const clientId of new Set(bookings.map((b) => b.clientId))) {
    try {
      total += await prisma.$transaction((tx) => releasePendingTips(tx, clientId));
    } catch (err) {
      logger.error('No se pudieron liberar propinas por cobrar', { clientId, err });
    }
  }
  return total;
}
