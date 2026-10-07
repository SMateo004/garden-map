/**
 * Guardería de varios días: una reserva normal por día, unidas por
 * Booking.bookingGroupId. Mientras no están pagadas se comportan como una sola
 * compra — un único QR/pago, y si se cancela o vence el pago caen todas juntas —;
 * una vez pagadas, cada día sigue su propio ciclo (aceptación del cuidador,
 * inicio, cierre, cancelación con su propio reembolso, disputa).
 *
 * El pago siempre se hace sobre la "reserva líder" del grupo (el primer día
 * todavía sin pagar): ahí quedan el QR, la donación, la deuda recuperada y el
 * código promocional. Al confirmarse ese pago, por cualquier camino (QR, banco,
 * admin), markGroupSiblingsPaid marca el resto en la MISMA transacción.
 */
import { BookingStatus, Prisma, RefundStatus } from '@prisma/client';
import prisma from '../../config/database.js';
import logger from '../../shared/logger.js';
import { track } from '../../shared/analytics.js';
import * as notificationService from '../../services/notification.service.js';
import { enqueueBookingCreate, enqueueSafely } from '../../services/chain-registry.service.js';

type Db = Prisma.TransactionClient | typeof prisma;

/** Estados "todavía sin pagar" en los que el grupo se mueve en bloque. */
const UNPAID_STATUSES: BookingStatus[] = [BookingStatus.PENDING_PAYMENT, BookingStatus.PAYMENT_PENDING_APPROVAL];

export interface BookingGroupSummary {
  id: string;
  /** Reserva sobre la que se paga (QR, donación, promo) — el primer día sin pagar. */
  leadId: string;
  size: number;
  days: Array<{
    id: string;
    date: string | null;
    timeSlot: string | null;
    startTime: string | null;
    status: string;
    totalAmount: string;
  }>;
  /** Suma de los días que faltan pagar (PENDING_PAYMENT) — lo que cobra el QR, sin donación ni deuda. */
  pendingAmount: string;
  /** Impuestos incluidos en pendingAmount. */
  pendingTaxAmount: string;
  /** Suma de todos los días no cancelados (para el comprobante una vez pagado). */
  totalAmount: string;
  taxAmount: string;
}

function orderedMembers(db: Db, bookingGroupId: string) {
  return db.booking.findMany({
    where: { bookingGroupId },
    orderBy: [{ walkDate: 'asc' }, { createdAt: 'asc' }],
    select: {
      id: true, walkDate: true, timeSlot: true, startTime: true, status: true,
      totalAmount: true, taxAmount: true, paidAt: true,
    },
  });
}

export async function getGroupSummary(db: Db, bookingGroupId: string): Promise<BookingGroupSummary | null> {
  const members = await orderedMembers(db, bookingGroupId);
  if (members.length === 0) return null;
  const pending = members.filter((m) => m.status === BookingStatus.PENDING_PAYMENT && !m.paidAt);
  const lead = pending[0] ?? members.find((m) => UNPAID_STATUSES.includes(m.status) && !m.paidAt) ?? members[0]!;
  const active = members.filter((m) => m.status !== BookingStatus.CANCELLED);
  const sumOf = (list: typeof members, key: 'totalAmount' | 'taxAmount') =>
    Math.round(list.reduce((s, m) => s + Number(m[key] ?? 0), 0) * 100) / 100;
  return {
    id: bookingGroupId,
    leadId: lead.id,
    size: members.length,
    days: members.map((m) => ({
      id: m.id,
      date: m.walkDate?.toISOString().slice(0, 10) ?? null,
      timeSlot: m.timeSlot ?? null,
      startTime: m.startTime ?? null,
      status: m.status,
      totalAmount: String(m.totalAmount),
    })),
    pendingAmount: String(sumOf(pending, 'totalAmount')),
    pendingTaxAmount: String(sumOf(pending, 'taxAmount')),
    totalAmount: String(sumOf(active, 'totalAmount')),
    taxAmount: String(sumOf(active, 'taxAmount')),
  };
}

/**
 * Para iniciar un pago: si la reserva es parte de un grupo, devuelve la líder
 * (primer día PENDING_PAYMENT del cliente) — así da igual desde qué día se
 * abra la pantalla de pago, nunca se generan dos QR para el mismo grupo.
 */
export async function resolvePaymentLeadId(bookingId: string, clientId: string): Promise<string> {
  const booking = await prisma.booking.findFirst({
    where: { id: bookingId, clientId },
    select: { bookingGroupId: true },
  });
  if (!booking?.bookingGroupId) return bookingId;
  const lead = await prisma.booking.findFirst({
    where: { bookingGroupId: booking.bookingGroupId, clientId, status: BookingStatus.PENDING_PAYMENT, paidAt: null },
    orderBy: [{ walkDate: 'asc' }, { createdAt: 'asc' }],
    select: { id: true },
  });
  return lead?.id ?? bookingId;
}

/**
 * Llamar dentro de la misma transacción que marca pagada a [bookingId]: marca
 * pagados los demás días sin pagar de su grupo. Devuelve los ids marcados para
 * que el llamador dispare después (fuera de la transacción) los efectos de
 * afterGroupSiblingsPaid. No-op para reservas sueltas.
 */
export async function markGroupSiblingsPaid(tx: Prisma.TransactionClient, bookingId: string): Promise<string[]> {
  const booking = await tx.booking.findUnique({ where: { id: bookingId }, select: { bookingGroupId: true } });
  if (!booking?.bookingGroupId) return [];
  await tx.$queryRaw`SELECT id FROM "bookings" WHERE "bookingGroupId" = ${booking.bookingGroupId} FOR UPDATE`;
  const siblings = await tx.booking.findMany({
    where: { bookingGroupId: booking.bookingGroupId, id: { not: bookingId }, status: { in: UNPAID_STATUSES }, paidAt: null },
    select: { id: true },
  });
  if (siblings.length === 0) return [];
  const ids = siblings.map((s) => s.id);
  await tx.booking.updateMany({
    where: { id: { in: ids }, status: { in: UNPAID_STATUSES }, paidAt: null },
    data: { status: BookingStatus.WAITING_CAREGIVER_APPROVAL, paidAt: new Date() },
  });
  return ids;
}

/** Efectos posteriores al pago de los demás días: aviso al cuidador, blockchain, analítica. */
export function afterGroupSiblingsPaid(ids: string[], clientId: string, method: string): void {
  for (const id of ids) {
    notificationService.onBookingWaitingApproval(id).catch((err) => {
      logger.error('Notification onBookingWaitingApproval failed (grupo)', { bookingId: id, err });
    });
    enqueueSafely('CREATE', () => enqueueBookingCreate(id));
    track(clientId, 'payment_completed', { bookingId: id, method, grouped: true });
  }
  if (ids.length > 0) logger.info('Grupo de reservas: días adicionales marcados pagados', { ids, method });
}

/**
 * Pago manual rechazado por un admin: los demás días que esperaban esa misma
 * aprobación vuelven a PENDING_PAYMENT junto con [bookingId].
 */
export async function revertGroupSiblingsToPending(tx: Prisma.TransactionClient, bookingId: string): Promise<void> {
  const booking = await tx.booking.findUnique({ where: { id: bookingId }, select: { bookingGroupId: true } });
  if (!booking?.bookingGroupId) return;
  await tx.booking.updateMany({
    where: {
      bookingGroupId: booking.bookingGroupId,
      id: { not: bookingId },
      status: BookingStatus.PAYMENT_PENDING_APPROVAL,
      paidAt: null,
    },
    data: { status: BookingStatus.PENDING_PAYMENT },
  });
}

/**
 * [bookingId] se canceló antes de pagarse (el cliente salió del pago, venció
 * el QR): los demás días sin pagar de su grupo caen con ella. Nunca toca días
 * ya pagados — esos se cancelan uno por uno con su propio reembolso.
 */
export async function cancelUnpaidGroupSiblings(
  tx: Prisma.TransactionClient,
  bookingId: string,
  cancellationReason: string | null,
  cancellationSource: string | null
): Promise<number> {
  const booking = await tx.booking.findUnique({ where: { id: bookingId }, select: { bookingGroupId: true } });
  if (!booking?.bookingGroupId) return 0;
  const result = await tx.booking.updateMany({
    where: {
      bookingGroupId: booking.bookingGroupId,
      id: { not: bookingId },
      status: { in: UNPAID_STATUSES },
      paidAt: null,
    },
    data: {
      status: BookingStatus.CANCELLED,
      cancelledAt: new Date(),
      cancellationReason,
      cancellationSource,
      refundAmount: new Prisma.Decimal(0),
      refundStatus: RefundStatus.REJECTED,
    },
  });
  return result.count;
}
