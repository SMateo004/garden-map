import type { BlockchainRecord, Prisma } from '@prisma/client';
import prisma from '../config/database.js';
import logger from '../shared/logger.js';
import { sendPushToAdmins } from './firebase.service.js';
import { caregiverNetOf } from '../modules/pricing/pricing.service.js';
import { isTestAccountEmail } from '../shared/test-accounts.js';
import {
  blockchainService,
  ChainRevertError,
  GasTooHighError,
  CANCEL_REASON_CODE,
  EXTENSION_UNIT_CODE,
  PROFILE_ROLE_CODE,
  SERVICE_TYPE_CODE,
  VERDICT_CODE,
  explorerTxUrl,
  networkInfo,
  toCents,
  toUnix,
  uuidToBytes16,
  type ChainReadiness,
  type ChainTarget,
} from './blockchain.service.js';

// ─────────────────────────────────────────────────────────────────────────────
// Cola persistente de registros on-chain (patrón outbox).
//
// Cada hecho que los Términos prometen registrar (pago, extensión, fin,
// cancelación, veredicto de disputa, perfil) se guarda PRIMERO como fila
// BlockchainRecord — idealmente en la misma transacción que el cambio de
// negocio — y después el job blockchain-sync lo envía a la cadena. Un error de
// RPC, falta de saldo, gas caro o un reinicio del servidor solo lo demoran:
// la fila queda PENDING y se reintenta con backoff hasta quedar CONFIRMED con
// su txHash. Un revert del contrato (no tiene sentido reintentar) la deja
// FAILED y avisa a los admins, que pueden reintentarla desde el panel.
//
// reconcile() cubre lo que ningún llamador encoló (caminos de pago por admin,
// jobs, código viejo): busca reservas pagadas/terminadas sin su fila.
//
// Antes de esto (hasta 2026-10-04) cada escritura era fire-and-forget en
// memoria: en modo deshabilitado devolvía null sin dejar rastro, y 15 reservas
// pagadas entre julio y agosto quedaron sin registro y sin alerta.
// ─────────────────────────────────────────────────────────────────────────────

export type ChainRecordKind = 'CREATE' | 'EXTEND' | 'FINALIZE' | 'CANCEL' | 'DISPUTE' | 'PROFILE';
type Db = Prisma.TransactionClient | typeof prisma;

/** Desde esta fecha (pago) las reservas se registran on-chain. Las anteriores no: ver Términos, sección 19. */
export const DEFAULT_RECORDS_SINCE = '2026-10-04T00:00:00-04:00';

export function recordsSince(): Date {
  return new Date(process.env.BLOCKCHAIN_RECORDS_SINCE || DEFAULT_RECORDS_SINCE);
}

const TERMINAL_KINDS: ChainRecordKind[] = ['FINALIZE', 'CANCEL', 'DISPUTE'];
const BACKOFF_MINUTES = [1, 2, 5, 15, 30, 60, 180, 360];
const ALERT_AFTER_ATTEMPTS = 3;

// ─── Encolar ────────────────────────────────────────────────────────────────

async function enqueue(
  db: Db,
  row: { subjectType: 'BOOKING' | 'USER'; subjectId: string; kind: ChainRecordKind; dedupeKey: string; payload?: Prisma.InputJsonValue },
): Promise<void> {
  // createMany + skipDuplicates = INSERT ... ON CONFLICT DO NOTHING: seguro dentro
  // de una $transaction del llamador (un create con P2002 la abortaría entera).
  await db.blockchainRecord.createMany({ data: [row], skipDuplicates: true });
  kickSoon();
}

/** Pago confirmado. Los datos (monto, fechas, partes) se leen de la reserva al enviar. */
export function enqueueBookingCreate(bookingId: string, db: Db = prisma): Promise<void> {
  return enqueue(db, { subjectType: 'BOOKING', subjectId: bookingId, kind: 'CREATE', dedupeKey: `CREATE:${bookingId}` });
}

/** Pago liberado al cuidador. rating 1-5, o null/0 si se liberó sin calificación. */
export function enqueueBookingFinalize(bookingId: string, rating: number | null, db: Db = prisma): Promise<void> {
  return enqueue(db, {
    subjectType: 'BOOKING', subjectId: bookingId, kind: 'FINALIZE', dedupeKey: `FINALIZE:${bookingId}`,
    payload: { rating: rating && rating >= 1 && rating <= 5 ? Math.round(rating) : 0 },
  });
}

/** Cancelación o rechazo de una reserva ya pagada (motivo y reembolso se leen al enviar). */
export function enqueueBookingCancel(bookingId: string, db: Db = prisma): Promise<void> {
  return enqueue(db, { subjectType: 'BOOKING', subjectId: bookingId, kind: 'CANCEL', dedupeKey: `CANCEL:${bookingId}` });
}

export function enqueueBookingExtension(
  bookingId: string,
  ext: { unit: 'MINUTES' | 'DAYS'; quantity: number; newTotalAmount: number },
  db: Db = prisma,
): Promise<void> {
  const newAmountCents = toCents(ext.newTotalAmount).toString();
  return enqueue(db, {
    subjectType: 'BOOKING', subjectId: bookingId, kind: 'EXTEND',
    // El total crece con cada extensión: identifica una extensión concreta.
    dedupeKey: `EXTEND:${bookingId}:${ext.unit}:${ext.quantity}:${newAmountCents}`,
    payload: { unit: ext.unit, quantity: Math.round(ext.quantity), newAmountCents },
  });
}

/**
 * Veredicto de disputa. `phase` = INITIAL (IA o resolución manual) o APPEAL
 * (apelación resuelta por el equipo): ambas quedan como eventos on-chain.
 */
export function enqueueDisputeResolution(
  bookingId: string,
  d: { verdict: string; caregiverAmount: number; clientAmount: number; phase: 'INITIAL' | 'APPEAL' },
  db: Db = prisma,
): Promise<void> {
  if (!VERDICT_CODE[d.verdict]) return Promise.resolve();
  return enqueue(db, {
    subjectType: 'BOOKING', subjectId: bookingId, kind: 'DISPUTE', dedupeKey: `DISPUTE:${bookingId}:${d.phase}`,
    payload: {
      verdict: d.verdict,
      caregiverCents: toCents(Math.max(0, d.caregiverAmount)).toString(),
      clientCents: toCents(Math.max(0, d.clientAmount)).toString(),
    },
  });
}

/** Alta de perfil o cambio de verificación: solo rol y verificado, con referencia seudónima. */
export function enqueueProfileSync(userId: string, role: 'CLIENT' | 'CAREGIVER', verified: boolean, db: Db = prisma): Promise<void> {
  return enqueue(db, {
    subjectType: 'USER', subjectId: userId, kind: 'PROFILE', dedupeKey: `PROFILE:${userId}:${role}:${verified ? 1 : 0}`,
    payload: { role, verified },
  });
}

/** Igual que enqueueProfileSync, leyendo el rol del usuario (verificación de identidad). */
export async function enqueueProfileSyncForUser(userId: string, verified: boolean): Promise<void> {
  const user = await prisma.user.findUnique({ where: { id: userId }, select: { role: true } });
  if (user?.role !== 'CLIENT' && user?.role !== 'CAREGIVER') return;
  await enqueueProfileSync(userId, user.role, verified);
}

/** Envoltorio para llamadores fuera de transacción: nunca rompe el flujo de negocio. */
export function enqueueSafely(label: string, fn: () => Promise<void>): void {
  fn().catch((err) => logger.error(`[Blockchain] No se pudo encolar ${label}`, { error: err?.message ?? err }));
}

// ─── Procesar ───────────────────────────────────────────────────────────────

let running = false;
let kickTimer: NodeJS.Timeout | null = null;

/** Procesa la cola unos segundos después (da tiempo a que el commit del llamador termine). */
function kickSoon(): void {
  if (process.env.NODE_ENV === 'test' || kickTimer) return;
  kickTimer = setTimeout(() => {
    kickTimer = null;
    processQueue().catch((err) => logger.error('[Blockchain] processQueue falló', { error: err?.message ?? err }));
  }, 3_000);
  kickTimer.unref?.();
}

type Plan =
  | { action: 'send'; target: ChainTarget; method: string; args: unknown[]; payload: Prisma.InputJsonValue }
  | { action: 'skip'; reason: string }
  | { action: 'wait'; reason: string; minutes?: number };

export interface ProcessSummary {
  paused?: string;
  busy?: boolean;
  confirmed: number;
  failed: number;
  retried: number;
  skipped: number;
  waiting: number;
}

/** Un ciclo del worker. Seguro de llamar en paralelo (un solo ciclo a la vez por proceso). */
export async function processQueue(limit = 25): Promise<ProcessSummary> {
  const summary: ProcessSummary = { confirmed: 0, failed: 0, retried: 0, skipped: 0, waiting: 0 };
  if (running) return { ...summary, busy: true };
  running = true;
  try {
    const ready = await blockchainService.checkReady();
    if (!ready.ok) return { ...summary, paused: ready.reason };

    await checkSentRecords(ready, summary);

    const rows = await prisma.blockchainRecord.findMany({
      where: { status: 'PENDING', nextAttemptAt: { lte: new Date() } },
      orderBy: { createdAt: 'asc' },
      take: limit,
    });
    for (const row of rows) {
      await processOne(row, ready, summary);
    }
    return summary;
  } finally {
    running = false;
  }
}

async function processOne(row: BlockchainRecord, ready: ChainReadiness, summary: ProcessSummary): Promise<void> {
  let plan: Plan;
  try {
    plan = await planFor(row, ready);
  } catch (err: any) {
    // Datos que no se pueden traducir (ej. id que no es uuid): reintentar no lo arregla.
    await markFailed(row, `No se pudo preparar el registro: ${err?.message ?? err}`);
    summary.failed++;
    return;
  }

  if (plan.action === 'skip') {
    await prisma.blockchainRecord.update({ where: { id: row.id }, data: { status: 'SKIPPED', lastError: plan.reason } });
    summary.skipped++;
    return;
  }
  if (plan.action === 'wait') {
    await prisma.blockchainRecord.update({
      where: { id: row.id },
      data: { lastError: plan.reason, nextAttemptAt: new Date(Date.now() + (plan.minutes ?? 1) * 60_000) },
    });
    summary.waiting++;
    return;
  }

  const attempts = row.attempts + 1;
  try {
    const { hash, sentBlock } = await blockchainService.send(plan.target, plan.method, plan.args, ready.chainId!);
    // El hash se guarda ANTES de esperar la confirmación: si el proceso muere
    // acá, checkSentRecords() retoma desde el hash en vez de reenviar.
    const sent = await prisma.blockchainRecord.update({
      where: { id: row.id },
      data: {
        status: 'SENT', attempts, txHash: hash, sentAt: new Date(), sentBlock,
        chainId: ready.chainId!, contractAddress: plan.target === 'escrow' ? ready.escrowAddress! : ready.profilesAddress!,
        payload: plan.payload, lastError: null,
      },
    });
    const receipt = await blockchainService.waitForReceipt(hash);
    if (!receipt) return; // sigue SENT; el próximo ciclo revisa
    await settleReceipt(sent, receipt.status === 1, receipt.blockNumber, summary);
  } catch (err) {
    await handleSendError(row, attempts, plan, err, ready, summary);
  }
}

async function handleSendError(
  row: BlockchainRecord, attempts: number, plan: Extract<Plan, { action: 'send' }>, err: any,
  ready: ChainReadiness, summary: ProcessSummary,
): Promise<void> {
  if (err instanceof GasTooHighError) {
    await prisma.blockchainRecord.update({
      where: { id: row.id },
      data: { lastError: err.message, nextAttemptAt: new Date(Date.now() + 5 * 60_000) },
    });
    summary.waiting++;
    return;
  }

  if (err instanceof ChainRevertError) {
    // "Ya está hecho" on-chain (ej. el servidor se reinició después de enviar
    // y antes de guardar el hash): se recupera el hash desde los eventos.
    const alreadyDone =
      (plan.method === 'recordBooking' && err.errorName === 'AlreadyRecorded') ||
      (['finalizeBooking', 'cancelBooking'].includes(plan.method) && err.errorName === 'NotActive');
    if (alreadyDone && row.subjectType === 'BOOKING') {
      const found = await blockchainService
        .findEventTx(plan.method, uuidToBytes16(row.subjectId), row.sentBlock)
        .catch(() => null);
      if (found) {
        const updated = await prisma.blockchainRecord.update({
          where: { id: row.id },
          data: {
            txHash: found.hash, chainId: ready.chainId!, contractAddress: ready.escrowAddress!, attempts,
            payload: plan.payload, lastError: 'Recuperado desde los eventos del contrato',
          },
        });
        await settleReceipt(updated, true, found.blockNumber, summary);
        return;
      }
    }
    await markFailed(row, `El contrato rechazó ${plan.method}: ${err.errorName}`, attempts);
    summary.failed++;
    return;
  }

  const message = String(err?.shortMessage || err?.reason || err?.message || err).slice(0, 450);
  const delay = BACKOFF_MINUTES[Math.min(attempts - 1, BACKOFF_MINUTES.length - 1)]!;
  const insufficientFunds = err?.code === 'INSUFFICIENT_FUNDS';
  const updated = await prisma.blockchainRecord.update({
    where: { id: row.id },
    data: { attempts, lastError: message, nextAttemptAt: new Date(Date.now() + delay * 60_000) },
  });
  summary.retried++;
  logger.warn('[Blockchain] Envío falló, se reintenta', { id: row.id, kind: row.kind, subjectId: row.subjectId, attempts, delay, message });
  if (!updated.alertedAt && (attempts >= ALERT_AFTER_ATTEMPTS || insufficientFunds)) {
    await alertAdmins(updated, insufficientFunds
      ? 'Sin saldo en el wallet de blockchain: recarga POL. Los registros quedan en cola y se envían solos.'
      : `Lleva ${attempts} intentos fallidos (${message.slice(0, 120)}). Sigue reintentando solo.`);
  }
}

async function settleReceipt(row: BlockchainRecord, success: boolean, blockNumber: number, summary: ProcessSummary): Promise<void> {
  if (!success) {
    await markFailed(row, 'La transacción se minó pero revirtió');
    summary.failed++;
    return;
  }
  await prisma.blockchainRecord.update({
    where: { id: row.id },
    data: { status: 'CONFIRMED', blockNumber, confirmedAt: new Date() },
  });
  // Columnas históricas de Booking (las lee el panel admin y código viejo).
  if (row.subjectType === 'BOOKING' && row.txHash) {
    const column = row.kind === 'CREATE' ? 'blockchainTxHash'
      : row.kind === 'FINALIZE' ? 'blockchainFinalizedTxHash'
      : row.kind === 'CANCEL' ? 'blockchainCancelledTxHash' : null;
    if (column) {
      await prisma.booking.update({ where: { id: row.subjectId }, data: { [column]: row.txHash } }).catch(() => {});
    }
  }
  summary.confirmed++;
  logger.info('[Blockchain] Registro confirmado', { kind: row.kind, subjectId: row.subjectId, txHash: row.txHash, blockNumber });
}

/** Txs enviadas sin confirmar (timeout o reinicio): confirma, reenvía si la red la descartó, o avisa si está trabada. */
async function checkSentRecords(ready: ChainReadiness, summary: ProcessSummary): Promise<void> {
  const sent = await prisma.blockchainRecord.findMany({ where: { status: 'SENT' }, orderBy: { sentAt: 'asc' }, take: 50 });
  for (const row of sent) {
    if (!row.txHash) continue;
    try {
      const receipt = await blockchainService.getReceipt(row.txHash);
      if (receipt) {
        if ((await blockchainService.getConfirmations(receipt)) >= 2) {
          await settleReceipt(row, receipt.status === 1, receipt.blockNumber, summary);
        }
        continue;
      }
      const ageMin = (Date.now() - (row.sentAt?.getTime() ?? 0)) / 60_000;
      if (ageMin < 10) continue;
      if (!(await blockchainService.isKnownTransaction(row.txHash))) {
        // La red la descartó (nunca se va a minar): volver a la cola. Si por
        // casualidad sí entró, el reenvío revierte con "ya hecho" y se recupera el hash.
        await prisma.blockchainRecord.update({
          where: { id: row.id },
          data: { status: 'PENDING', lastError: `tx ${row.txHash} descartada por la red; se reenvía`, nextAttemptAt: new Date() },
        });
        summary.retried++;
      } else if (ageMin > 30 && !row.alertedAt) {
        await alertAdmins(row, `Transacción enviada hace ${Math.round(ageMin)} min y sin confirmar (${row.txHash}).`);
      }
    } catch (err: any) {
      logger.warn('[Blockchain] No se pudo revisar una tx enviada', { id: row.id, error: err?.message ?? err });
    }
  }
  void ready;
}

// ─── Qué enviar para cada fila ──────────────────────────────────────────────

function cancelReasonCode(b: { status: string; cancellationSource: string | null }): number {
  if (b.status === 'REJECTED_BY_CAREGIVER') return CANCEL_REASON_CODE.REJECTED_BY_CAREGIVER;
  const s = b.cancellationSource ?? '';
  if (s.startsWith('ADMIN')) return CANCEL_REASON_CODE.ADMIN;
  if (s === 'NO_SHOW') return CANCEL_REASON_CODE.NO_SHOW;
  if (s === 'CLIENT') return CANCEL_REASON_CODE.CLIENT;
  // Incompatibilidad en el Meet & Greet: la decide el cuidador.
  if (s.startsWith('CAREGIVER') || s === 'MG_INCOMPATIBLE') return CANCEL_REASON_CODE.CAREGIVER;
  if (s === 'QR_ABANDONED' || s === 'PAYMENT_TIMEOUT') return CANCEL_REASON_CODE.PAYMENT_TIMEOUT;
  if (s) return CANCEL_REASON_CODE.SYSTEM;
  return CANCEL_REASON_CODE.UNSPECIFIED;
}

/** Fecha de inicio y fin del servicio, como en el detalle de la reserva. */
function serviceWindow(b: {
  startDate: Date | null; endDate: Date | null; walkDate: Date | null;
  startTime: string | null; duration: number | null; paidAt: Date | null; createdAt: Date;
}): { start: Date; end: Date } {
  let start = b.startDate ?? b.walkDate ?? b.paidAt ?? b.createdAt;
  if (!b.startDate && b.walkDate && b.startTime && /^\d{1,2}:\d{2}$/.test(b.startTime)) {
    const [h, m] = b.startTime.split(':').map(Number);
    const d = new Date(b.walkDate);
    // Hora local de Bolivia (UTC-4).
    d.setUTCHours(h! + 4, m!, 0, 0);
    start = d;
  }
  let end = b.endDate ?? null;
  if (!end && b.duration) end = new Date(start.getTime() + b.duration * 60_000);
  if (!end || end < start) end = start;
  return { start, end };
}

async function planFor(row: BlockchainRecord, ready: ChainReadiness): Promise<Plan> {
  if (row.subjectType === 'USER') {
    const user = await prisma.user.findUnique({ where: { id: row.subjectId }, select: { email: true } });
    if (isTestAccountEmail(user?.email)) return { action: 'skip', reason: 'Cuenta de prueba (reviewer.*): no se registra' };
    if (!ready.profilesAddress) return { action: 'skip', reason: 'GardenProfiles no configurado (BLOCKCHAIN_PROFILES_ADDRESS)' };
    if (!ready.profilesOk) return { action: 'wait', reason: 'GardenProfiles desactualizado o el wallet no es su recorder', minutes: 60 };
    const p = (row.payload ?? {}) as { role?: string; verified?: boolean };
    const role = PROFILE_ROLE_CODE[p.role ?? ''];
    if (!role) return { action: 'skip', reason: `Rol sin registro on-chain: ${p.role}` };
    return {
      action: 'send', target: 'profiles', method: 'syncProfile',
      args: [blockchainService.partyRef(row.subjectId), role, !!p.verified],
      payload: { role: p.role ?? null, verified: !!p.verified },
    };
  }

  const booking = await prisma.booking.findUnique({
    where: { id: row.subjectId },
    select: {
      id: true, status: true, serviceType: true, totalAmount: true, paidAt: true, createdAt: true,
      startDate: true, endDate: true, walkDate: true, startTime: true, duration: true,
      clientId: true, cancellationSource: true, refundAmount: true, refundStatus: true, createdByAdmin: true,
      client: { select: { email: true } },
      caregiver: { select: { userId: true, user: { select: { email: true } } } },
    },
  });
  if (!booking) return { action: 'skip', reason: 'La reserva ya no existe' };
  if (!booking.paidAt) return { action: 'skip', reason: 'Reserva sin pago: no se registra' };
  if (booking.createdByAdmin) return { action: 'skip', reason: 'Reserva de prueba creada por un admin: no se registra' };
  // Cuentas de prueba de las tiendas / pruebas en vivo: nada de ellas queda en la red principal.
  if (isTestAccountEmail(booking.client?.email) || isTestAccountEmail(booking.caregiver?.user?.email)) {
    return { action: 'skip', reason: 'Reserva de una cuenta de prueba (reviewer.*): no se registra' };
  }
  const since = recordsSince();
  if (booking.paidAt < since) return { action: 'skip', reason: `Pagada antes del ${since.toISOString()}: fuera del registro on-chain` };
  const id16 = uuidToBytes16(booking.id);

  if (row.kind === 'CREATE') {
    const st = SERVICE_TYPE_CODE[booking.serviceType];
    if (!st) return { action: 'skip', reason: `Tipo de servicio sin código on-chain: ${booking.serviceType}` };
    const { start, end } = serviceWindow(booking as any);
    const amountCents = toCents(booking.totalAmount as any);
    return {
      action: 'send', target: 'escrow', method: 'recordBooking',
      args: [
        id16, blockchainService.partyRef(booking.clientId), blockchainService.partyRef(booking.caregiver.userId),
        st, amountCents, toUnix(booking.paidAt), toUnix(start), toUnix(end),
      ],
      payload: {
        serviceType: booking.serviceType, amountCents: amountCents.toString(),
        paidAt: booking.paidAt.toISOString(), startTime: start.toISOString(), endTime: end.toISOString(),
      },
    };
  }

  // El resto depende de que el pago ya esté registrado.
  const create = await prisma.blockchainRecord.findUnique({ where: { dedupeKey: `CREATE:${booking.id}` } });
  if (!create) {
    await enqueueBookingCreate(booking.id);
    return { action: 'wait', reason: 'Esperando el registro del pago (encolado ahora)' };
  }
  if (create.status === 'SKIPPED') return { action: 'skip', reason: 'El pago de esta reserva no se registró on-chain' };
  if (create.status !== 'CONFIRMED') return { action: 'wait', reason: 'Esperando que se confirme el registro del pago' };

  if (row.kind === 'FINALIZE' || row.kind === 'CANCEL') {
    // Un veredicto de disputa ya cerró la reserva on-chain.
    const dispute = await prisma.blockchainRecord.findFirst({
      where: { subjectId: booking.id, kind: 'DISPUTE', status: { in: ['PENDING', 'SENT', 'CONFIRMED'] } },
    });
    if (dispute) return { action: 'skip', reason: 'La reserva se cerró on-chain con el veredicto de la disputa' };
    const otherTerminal = await prisma.blockchainRecord.findFirst({
      where: { subjectId: booking.id, kind: row.kind === 'FINALIZE' ? 'CANCEL' : 'FINALIZE', status: 'CONFIRMED' },
    });
    if (otherTerminal) return { action: 'skip', reason: `Ya se registró ${otherTerminal.kind} para esta reserva` };
  }

  if (row.kind === 'FINALIZE') {
    const rating = Number((row.payload as any)?.rating ?? 0);
    return { action: 'send', target: 'escrow', method: 'finalizeBooking', args: [id16, rating], payload: { rating } };
  }

  if (row.kind === 'CANCEL') {
    const reason = cancelReasonCode(booking);
    const refunded = booking.refundAmount != null && ['PROCESSED', 'APPROVED'].includes(booking.refundStatus ?? '');
    const refundCents = refunded ? toCents(booking.refundAmount as any) : 0n;
    return {
      action: 'send', target: 'escrow', method: 'cancelBooking', args: [id16, reason, refundCents],
      payload: { reasonCode: reason, refundCents: refundCents.toString() },
    };
  }

  if (row.kind === 'EXTEND') {
    const p = row.payload as { unit: 'MINUTES' | 'DAYS'; quantity: number; newAmountCents: string };
    const terminal = await prisma.blockchainRecord.findFirst({
      where: { subjectId: booking.id, kind: { in: TERMINAL_KINDS }, status: 'CONFIRMED' },
    });
    if (terminal) return { action: 'skip', reason: 'La reserva ya está cerrada on-chain' };
    return {
      action: 'send', target: 'escrow', method: 'extendBooking',
      args: [id16, EXTENSION_UNIT_CODE[p.unit], p.quantity, BigInt(p.newAmountCents)],
      payload: p,
    };
  }

  if (row.kind === 'DISPUTE') {
    const p = row.payload as { verdict: string; caregiverCents: string; clientCents: string };
    return {
      action: 'send', target: 'escrow', method: 'resolveDispute',
      args: [id16, VERDICT_CODE[p.verdict], BigInt(p.caregiverCents), BigInt(p.clientCents)],
      payload: p,
    };
  }

  return { action: 'skip', reason: `Tipo de registro desconocido: ${row.kind}` };
}

// ─── Fallas y alertas ───────────────────────────────────────────────────────

async function markFailed(row: BlockchainRecord, reason: string, attempts?: number): Promise<void> {
  const updated = await prisma.blockchainRecord.update({
    where: { id: row.id },
    data: { status: 'FAILED', lastError: reason.slice(0, 450), ...(attempts ? { attempts } : {}) },
  });
  logger.error('[Blockchain] Registro FALLIDO — requiere revisión', { id: row.id, kind: row.kind, subjectId: row.subjectId, reason });
  await alertAdmins(updated, `${reason}. No se reintenta solo: revisa y reintenta desde el panel.`);
}

async function alertAdmins(row: BlockchainRecord, message: string): Promise<void> {
  await prisma.blockchainRecord.update({ where: { id: row.id }, data: { alertedAt: new Date() } }).catch(() => {});
  await prisma.adminNotification
    .create({ data: { type: 'BLOCKCHAIN_FAILURE', bookingId: row.subjectType === 'BOOKING' ? row.subjectId : null, caregiverId: '' } })
    .catch(() => {});
  const subject = row.subjectType === 'BOOKING' ? `Reserva ${row.subjectId.slice(0, 8).toUpperCase()}` : 'Perfil';
  sendPushToAdmins(
    'Registro blockchain con problemas',
    `${subject} · ${row.kind}: ${message}`.slice(0, 230),
    { type: 'BLOCKCHAIN_FAILURE', recordId: row.id },
  ).catch(() => {});
}

/** Admin: vuelve a poner en cola un registro FAILED (o adelanta uno PENDING). */
export async function retryRecord(recordId: string): Promise<BlockchainRecord | null> {
  const row = await prisma.blockchainRecord.findUnique({ where: { id: recordId } });
  if (!row || !['FAILED', 'PENDING'].includes(row.status)) return null;
  const updated = await prisma.blockchainRecord.update({
    where: { id: recordId },
    data: { status: 'PENDING', nextAttemptAt: new Date(), alertedAt: null, lastError: row.lastError },
  });
  kickSoon();
  return updated;
}

// ─── Reconciliación ─────────────────────────────────────────────────────────

/**
 * Encola lo que falte: reservas pagadas desde recordsSince() sin registro del
 * pago, terminadas sin su cierre y disputas resueltas sin su veredicto.
 */
export async function reconcile(): Promise<{ create: number; finalize: number; cancel: number; dispute: number }> {
  const since = recordsSince();
  const counts = { create: 0, finalize: 0, cancel: 0, dispute: 0 };

  const missingCreate = await prisma.$queryRaw<Array<{ id: string }>>`
    SELECT b.id FROM bookings b
    WHERE b."paidAt" >= ${since} AND b."createdByAdmin" = false
      AND NOT EXISTS (SELECT 1 FROM blockchain_records r WHERE r."dedupeKey" = 'CREATE:' || b.id)
    ORDER BY b."paidAt" ASC LIMIT 200`;
  for (const { id } of missingCreate) {
    await enqueueBookingCreate(id);
    counts.create++;
  }

  const missingFinalize = await prisma.$queryRaw<Array<{ id: string; ownerRating: number | null }>>`
    SELECT b.id, b."ownerRating" FROM bookings b
    WHERE b."paidAt" >= ${since} AND b."createdByAdmin" = false AND b.status = 'COMPLETED' AND b."payoutStatus" = 'PAID'
      AND NOT EXISTS (SELECT 1 FROM "Dispute" d WHERE d."bookingId" = b.id)
      AND NOT EXISTS (SELECT 1 FROM blockchain_records r WHERE r."dedupeKey" = 'FINALIZE:' || b.id)
    LIMIT 200`;
  for (const { id, ownerRating } of missingFinalize) {
    await enqueueBookingFinalize(id, ownerRating);
    counts.finalize++;
  }

  const missingCancel = await prisma.$queryRaw<Array<{ id: string }>>`
    SELECT b.id FROM bookings b
    WHERE b."paidAt" >= ${since} AND b."createdByAdmin" = false AND b.status IN ('CANCELLED', 'REJECTED_BY_CAREGIVER')
      AND NOT EXISTS (SELECT 1 FROM "Dispute" d WHERE d."bookingId" = b.id AND d.status IN ('RESOLVED', 'APPEALED'))
      AND NOT EXISTS (SELECT 1 FROM blockchain_records r WHERE r."dedupeKey" = 'CANCEL:' || b.id)
    LIMIT 200`;
  for (const { id } of missingCancel) {
    await enqueueBookingCancel(id);
    counts.cancel++;
  }

  const resolved = await prisma.dispute.findMany({
    where: {
      aiVerdict: { not: null },
      status: { in: ['RESOLVED', 'APPEALED'] },
      booking: { paidAt: { gte: since }, createdByAdmin: false },
    },
    select: {
      bookingId: true, aiVerdict: true, appealVerdict: true, appealResolvedAt: true,
      booking: { select: { totalAmount: true, commissionAmount: true, taxAmount: true } },
    },
    take: 500,
  });
  if (resolved.length > 0) {
    const existing = new Set(
      (await prisma.blockchainRecord.findMany({
        where: { kind: 'DISPUTE', subjectId: { in: resolved.map((d) => d.bookingId) } },
        select: { dedupeKey: true },
      })).map((r) => r.dedupeKey),
    );
    for (const d of resolved) {
      const phases: Array<['INITIAL' | 'APPEAL', string | null]> = [
        ['INITIAL', d.aiVerdict],
        ['APPEAL', d.appealResolvedAt ? d.appealVerdict : null],
      ];
      for (const [phase, verdict] of phases) {
        if (!verdict || existing.has(`DISPUTE:${d.bookingId}:${phase}`)) continue;
        await enqueueDisputeResolution(d.bookingId, { ...disputeAmounts(verdict, d.booking), phase });
        counts.dispute++;
      }
    }
  }

  const total = counts.create + counts.finalize + counts.cancel + counts.dispute;
  if (total > 0) logger.info('[Blockchain] Reconciliación encoló registros faltantes', counts);
  return counts;
}

/** Montos que se registran con cada veredicto (mismo reparto que applyResolution). */
export function disputeAmounts(
  verdict: string,
  booking: { totalAmount: unknown; commissionAmount: unknown; taxAmount?: unknown },
): { verdict: string; caregiverAmount: number; clientAmount: number } {
  const net = caregiverNetOf(booking);
  const total = Number(booking.totalAmount);
  if (verdict === 'CAREGIVER_WINS') return { verdict, caregiverAmount: net, clientAmount: 0 };
  if (verdict === 'CLIENT_WINS') return { verdict, caregiverAmount: 0, clientAmount: total };
  return { verdict, caregiverAmount: Math.round(net * 80) / 100, clientAmount: Math.round(net * 20) / 100 };
}

// ─── Comprobante para el usuario ────────────────────────────────────────────

const PROOF_LABELS: Record<string, string> = {
  CREATE: 'Pago registrado',
  EXTEND: 'Extensión registrada',
  FINALIZE: 'Servicio completado registrado',
  CANCEL: 'Cancelación registrada',
  DISPUTE: 'Veredicto de la disputa registrado',
};

export interface BookingChainProof {
  /** RECORDED: el pago ya está en la cadena. PENDING: en cola. NOT_APPLICABLE: no corresponde registro. */
  status: 'RECORDED' | 'PENDING' | 'NOT_APPLICABLE';
  reason: 'NOT_PAID' | 'BEFORE_START' | 'TEST_BOOKING' | null;
  recordsSince: string;
  network: { chainId: number; name: string; label: string; testnet: boolean } | null;
  records: Array<{ kind: string; label: string; txHash: string; explorerUrl: string | null; confirmedAt: string | null }>;
}

export async function getBookingChainProof(
  booking: { id: string; paidAt: Date | null; createdByAdmin?: boolean | null },
): Promise<BookingChainProof> {
  const since = recordsSince();
  const base = { recordsSince: since.toISOString(), network: null, records: [] };
  if (!booking.paidAt) return { status: 'NOT_APPLICABLE', reason: 'NOT_PAID', ...base };
  if (booking.createdByAdmin) return { status: 'NOT_APPLICABLE', reason: 'TEST_BOOKING', ...base };
  if (booking.paidAt < since) return { status: 'NOT_APPLICABLE', reason: 'BEFORE_START', ...base };

  const rows = await prisma.blockchainRecord.findMany({
    where: { subjectType: 'BOOKING', subjectId: booking.id, status: 'CONFIRMED' },
    orderBy: { confirmedAt: 'asc' },
  });
  const create = rows.find((r) => r.kind === 'CREATE');
  if (!create) return { status: 'PENDING', reason: null, ...base };
  const net = networkInfo(create.chainId)!;
  return {
    status: 'RECORDED',
    reason: null,
    recordsSince: since.toISOString(),
    network: { chainId: net.chainId, name: net.name, label: net.label, testnet: net.testnet },
    records: rows
      .filter((r) => r.txHash && r.chainId === create.chainId)
      .map((r) => ({
        kind: r.kind,
        label: PROOF_LABELS[r.kind] ?? r.kind,
        txHash: r.txHash!,
        explorerUrl: explorerTxUrl(r.chainId, r.txHash),
        confirmedAt: r.confirmedAt?.toISOString() ?? null,
      })),
  };
}

// ─── Panel admin ────────────────────────────────────────────────────────────

export async function getQueueOverview() {
  const [byStatus, problems, recent] = await Promise.all([
    prisma.blockchainRecord.groupBy({ by: ['status'], _count: { _all: true } }),
    prisma.blockchainRecord.findMany({
      where: { OR: [{ status: 'FAILED' }, { status: { in: ['PENDING', 'SENT'] }, attempts: { gte: ALERT_AFTER_ATTEMPTS } }] },
      orderBy: { updatedAt: 'desc' },
      take: 30,
    }),
    prisma.blockchainRecord.findMany({ where: { status: 'CONFIRMED' }, orderBy: { confirmedAt: 'desc' }, take: 10 }),
  ]);
  const counts: Record<string, number> = { PENDING: 0, SENT: 0, CONFIRMED: 0, FAILED: 0, SKIPPED: 0 };
  for (const s of byStatus) counts[s.status] = s._count._all;
  const shape = (r: BlockchainRecord) => ({
    id: r.id, kind: r.kind, subjectType: r.subjectType, subjectId: r.subjectId, status: r.status,
    attempts: r.attempts, lastError: r.lastError, txHash: r.txHash, explorerUrl: explorerTxUrl(r.chainId, r.txHash),
    createdAt: r.createdAt.toISOString(), confirmedAt: r.confirmedAt?.toISOString() ?? null,
  });
  return { counts, recordsSince: recordsSince().toISOString(), problems: problems.map(shape), recent: recent.map(shape) };
}
