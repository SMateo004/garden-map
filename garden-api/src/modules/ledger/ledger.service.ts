import { LedgerEntrySource, Prisma } from '@prisma/client';
import prisma from '../../config/database.js';
import { BadRequestError } from '../../shared/errors.js';
import logger from '../../shared/logger.js';
import { CHART_OF_ACCOUNTS, ACCOUNT } from './ledger.constants.js';
import type { CreateManualEntryBody } from './ledger.validation.js';

/** Sembrado del plan de cuentas — idempotente, se puede llamar tantas veces
 * como haga falta (ej. al arrancar el server, o antes de generar un libro). */
export async function seedAccounts(): Promise<void> {
  for (const acc of CHART_OF_ACCOUNTS) {
    await prisma.ledgerAccount.upsert({
      where: { code: acc.code },
      create: acc,
      update: { name: acc.name, type: acc.type },
    });
  }
}

async function getAccountMap(): Promise<Map<string, string>> {
  await seedAccounts();
  const accounts = await prisma.ledgerAccount.findMany();
  return new Map(accounts.map((a) => [a.code, a.id]));
}

function monthRange(year: number, month: number): { start: Date; end: Date } {
  const start = new Date(Date.UTC(year, month - 1, 1));
  const end = new Date(Date.UTC(year, month, 1)); // primer día del mes siguiente, exclusivo
  return { start, end };
}

/** Rol del dueño de una billetera → qué cuenta de pasivo usar. */
async function billeteraAccountForUser(userId: string, accountMap: Map<string, string>): Promise<string> {
  const user = await prisma.user.findUnique({ where: { id: userId }, select: { role: true } });
  const code = user?.role === 'CAREGIVER' ? ACCOUNT.BILLETERA_CUIDADORES : ACCOUNT.BILLETERA_CLIENTES;
  return accountMap.get(code)!;
}

/**
 * Regenera TODOS los asientos automáticos de un mes desde cero (nunca toca
 * los MANUAL) — se derivan siempre de datos ya existentes (WalletTransaction/
 * Booking), así que recalcularlos es seguro y no puede duplicar ni
 * desincronizarse. Ver comentario en el schema de Prisma para el diseño
 * completo de cada tipo de asiento.
 */
export async function regenerateAutoEntriesForMonth(year: number, month: number): Promise<{ created: number }> {
  const { start, end } = monthRange(year, month);
  const accountMap = await getAccountMap();

  // Borra solo los automáticos del mes — los manuales quedan intactos.
  await prisma.ledgerEntry.deleteMany({
    where: { date: { gte: start, lt: end }, source: { not: LedgerEntrySource.MANUAL } },
  });

  let created = 0;

  // ── AUTO_PAYMENT — un asiento por cada EARNING (pago liberado al
  // cuidador: al calificar, o auto-liberado a las 48h). Se reconoce el
  // ingreso de Garden EN ESE MOMENTO, no cuando el cliente pagó — es
  // cuando el servicio queda confirmado y el dinero de verdad se mueve.
  const earnings = await prisma.walletTransaction.findMany({
    where: { type: 'EARNING', status: 'COMPLETED', createdAt: { gte: start, lt: end }, bookingId: { not: null } },
    select: { id: true, amount: true, bookingId: true, userId: true, createdAt: true },
  });
  for (const earning of earnings) {
    const booking = await prisma.booking.findUnique({
      where: { id: earning.bookingId! },
      select: {
        id: true, totalAmount: true, commissionAmount: true, commissionAmountBeforePromo: true,
        walletPaymentAmount: true, petName: true, serviceType: true,
      },
    });
    if (!booking) continue;

    const totalAmount = Number(booking.totalAmount);
    const commissionAmount = Number(booking.commissionAmount);
    const grossCommission = booking.commissionAmountBeforePromo != null ? Number(booking.commissionAmountBeforePromo) : commissionAmount;
    const marketingExpense = Math.max(0, Math.round((grossCommission - commissionAmount) * 100) / 100);
    const caregiverCut = Number(earning.amount);
    const walletPortion = Math.min(Number(booking.walletPaymentAmount ?? 0), totalAmount);
    const bankPortion = Math.max(0, Math.round((totalAmount - walletPortion) * 100) / 100);

    const lines: Array<{ accountId: string; debit: number; credit: number }> = [];
    if (bankPortion > 0) lines.push({ accountId: accountMap.get(ACCOUNT.BANCO)!, debit: bankPortion, credit: 0 });
    if (walletPortion > 0) lines.push({ accountId: accountMap.get(ACCOUNT.BILLETERA_CLIENTES)!, debit: walletPortion, credit: 0 });
    if (marketingExpense > 0) lines.push({ accountId: accountMap.get(ACCOUNT.GASTO_MARKETING_PROMOS)!, debit: marketingExpense, credit: 0 });
    lines.push({ accountId: accountMap.get(ACCOUNT.BILLETERA_CUIDADORES)!, debit: 0, credit: caregiverCut });
    lines.push({ accountId: accountMap.get(ACCOUNT.INGRESO_COMISION)!, debit: 0, credit: grossCommission });

    const svcLabel = booking.serviceType === 'PASEO' ? 'paseo' : booking.serviceType === 'GUARDERIA' ? 'guardería' : 'hospedaje';
    await createEntryIfBalanced(
      LedgerEntrySource.AUTO_PAYMENT,
      earning.id,
      earning.createdAt,
      `Pago liberado — ${svcLabel} de ${booking.petName ?? 'mascota'} (reserva ${booking.id.slice(0, 8)})`,
      lines
    );
    created++;
  }

  // ── AUTO_WITHDRAWAL — retiro efectivamente pagado (sale plata real del banco).
  const withdrawals = await prisma.walletTransaction.findMany({
    where: { type: 'WITHDRAWAL', status: 'COMPLETED', createdAt: { gte: start, lt: end } },
    select: { id: true, amount: true, userId: true, createdAt: true, description: true },
  });
  for (const w of withdrawals) {
    const billeteraId = await billeteraAccountForUser(w.userId, accountMap);
    await createEntryIfBalanced(
      LedgerEntrySource.AUTO_WITHDRAWAL,
      w.id,
      w.createdAt,
      `Retiro pagado — ${w.description}`,
      [
        { accountId: billeteraId, debit: Number(w.amount), credit: 0 },
        { accountId: accountMap.get(ACCOUNT.BANCO)!, debit: 0, credit: Number(w.amount) },
      ]
    );
    created++;
  }

  // ── AUTO_REFERRAL — cada bono (referido y referente son 2 filas separadas,
  // cada una ya es un WalletTransaction propio — 1 asiento por fila).
  const referrals = await prisma.walletTransaction.findMany({
    where: { type: 'REFERRAL_BONUS', status: 'COMPLETED', createdAt: { gte: start, lt: end } },
    select: { id: true, amount: true, userId: true, createdAt: true, description: true },
  });
  for (const r of referrals) {
    const billeteraId = await billeteraAccountForUser(r.userId, accountMap);
    await createEntryIfBalanced(
      LedgerEntrySource.AUTO_REFERRAL,
      r.id,
      r.createdAt,
      `Bono de referido — ${r.description}`,
      [
        { accountId: accountMap.get(ACCOUNT.GASTO_MARKETING_REFERIDOS)!, debit: Number(r.amount), credit: 0 },
        { accountId: billeteraId, debit: 0, credit: Number(r.amount) },
      ]
    );
    created++;
  }

  // ── AUTO_REFUND — reembolsos acreditados a billetera de cliente.
  const refunds = await prisma.walletTransaction.findMany({
    where: { type: 'REFUND', status: 'COMPLETED', createdAt: { gte: start, lt: end } },
    select: { id: true, amount: true, userId: true, createdAt: true, description: true },
  });
  for (const rf of refunds) {
    const billeteraId = await billeteraAccountForUser(rf.userId, accountMap);
    await createEntryIfBalanced(
      LedgerEntrySource.AUTO_REFUND,
      rf.id,
      rf.createdAt,
      `Reembolso — ${rf.description}`,
      [
        { accountId: accountMap.get(ACCOUNT.GASTO_REEMBOLSOS)!, debit: Number(rf.amount), credit: 0 },
        { accountId: billeteraId, debit: 0, credit: Number(rf.amount) },
      ]
    );
    created++;
  }

  logger.info('[LEDGER] Asientos automáticos regenerados', { year, month, created });
  return { created };
}

async function createEntryIfBalanced(
  source: LedgerEntrySource,
  sourceRefId: string,
  date: Date,
  description: string,
  lines: Array<{ accountId: string; debit: number; credit: number }>
): Promise<void> {
  const totalDebit = Math.round(lines.reduce((s, l) => s + l.debit, 0) * 100);
  const totalCredit = Math.round(lines.reduce((s, l) => s + l.credit, 0) * 100);
  if (totalDebit !== totalCredit) {
    // No debería pasar nunca (la matemática de cada tipo de asiento está
    // pensada para cuadrar siempre) — si pasa, es un bug real y se loguea
    // en vez de generar un asiento roto que arruine el libro del mes.
    logger.error('[LEDGER] Asiento no balanceado, se omite', { source, sourceRefId, totalDebit, totalCredit });
    return;
  }
  await prisma.ledgerEntry.create({
    data: {
      date: new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate())),
      description,
      source,
      sourceRefId,
      lines: { create: lines },
    },
  });
}

export async function addManualEntry(adminUserId: string, body: CreateManualEntryBody) {
  const accountMap = await getAccountMap();
  const lines = body.lines.map((l) => {
    const accountId = accountMap.get(l.accountCode);
    if (!accountId) throw new BadRequestError(`Cuenta ${l.accountCode} no existe`, 'INVALID_ACCOUNT');
    return { accountId, debit: l.debit, credit: l.credit };
  });

  return prisma.ledgerEntry.create({
    data: {
      date: new Date(body.date + 'T00:00:00.000Z'),
      description: body.description,
      source: 'MANUAL',
      createdBy: adminUserId,
      lines: { create: lines },
    },
    include: { lines: { include: { account: true } } },
  });
}

export async function getAccounts() {
  await seedAccounts();
  return prisma.ledgerAccount.findMany({ orderBy: { code: 'asc' } });
}

/** Libro diario completo de un mes (automáticos regenerados + manuales ya
 * cargados) + resumen tipo estado de resultados. */
export async function getMonthlyLedger(year: number, month: number) {
  await regenerateAutoEntriesForMonth(year, month);
  const { start, end } = monthRange(year, month);

  const entries = await prisma.ledgerEntry.findMany({
    where: { date: { gte: start, lt: end } },
    include: { lines: { include: { account: true } } },
    orderBy: [{ date: 'asc' }, { createdAt: 'asc' }],
  });

  const summary = new Map<string, { code: string; name: string; type: string; debit: number; credit: number }>();
  for (const entry of entries) {
    for (const line of entry.lines) {
      const key = line.account.code;
      const prev = summary.get(key) ?? { code: line.account.code, name: line.account.name, type: line.account.type, debit: 0, credit: 0 };
      prev.debit += Number(line.debit);
      prev.credit += Number(line.credit);
      summary.set(key, prev);
    }
  }

  const ingresos = [...summary.values()].filter((s) => s.type === 'INGRESO');
  const gastos = [...summary.values()].filter((s) => s.type === 'GASTO');
  const totalIngresos = ingresos.reduce((s, a) => s + (a.credit - a.debit), 0);
  const totalGastos = gastos.reduce((s, a) => s + (a.debit - a.credit), 0);

  return {
    year,
    month,
    entries,
    cuentaSummary: [...summary.values()],
    estadoResultados: {
      ingresos: ingresos.map((a) => ({ code: a.code, name: a.name, amount: Math.round((a.credit - a.debit) * 100) / 100 })),
      gastos: gastos.map((a) => ({ code: a.code, name: a.name, amount: Math.round((a.debit - a.credit) * 100) / 100 })),
      totalIngresos: Math.round(totalIngresos * 100) / 100,
      totalGastos: Math.round(totalGastos * 100) / 100,
      utilidad: Math.round((totalIngresos - totalGastos) * 100) / 100,
    },
  };
}
