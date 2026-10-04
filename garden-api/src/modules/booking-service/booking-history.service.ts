import prisma from '../../config/database.js';
import { BookingNotFoundError, ForbiddenError } from '../../shared/errors.js';

/**
 * Historial independiente de UNA reserva: método de pago + línea de tiempo de
 * todo lo que pasó + movimientos de dinero. Se arma solo con lo que ya está
 * guardado (Booking, serviceEvents, WalletTransaction, Dispute, AdminAction),
 * así que también funciona con reservas anteriores a este endpoint.
 *
 * Cada parte ve lo suyo: el dueño nunca ve comisión/impuestos (regla de
 * negocio) y cada uno ve solo SUS movimientos de billetera.
 */

export type HistoryActor = 'CLIENTE' | 'CUIDADOR' | 'SISTEMA' | 'SOPORTE';

export interface HistoryEvent {
  at: string;
  kind: string;
  actor: HistoryActor;
  title: string;
  detail?: string | null;
  amount?: number | null;
}

export type PaymentMethodCode = 'WALLET' | 'QR' | 'CARD' | 'WALLET_QR' | 'WALLET_CARD' | 'OTHER' | 'PENDING';

export interface BookingHistory {
  bookingId: string;
  status: string;
  viewerRole: 'CLIENT' | 'CAREGIVER' | 'ADMIN';
  payment: {
    method: PaymentMethodCode;
    methodLabel: string;
    status: 'PENDING' | 'PAID' | 'REFUNDED' | 'PARTIALLY_REFUNDED';
    totalAmount: number;
    walletAmount: number;
    externalAmount: number;
    donationAmount: number;
    paidAt: string | null;
    approvedBySupport: boolean;
    reference: string | null;
    refundAmount: number | null;
    refundStatus: string | null;
    /** Solo para el cuidador/admin. */
    caregiverNetAmount?: number;
    commissionAmount?: number;
    taxAmount?: number;
  };
  timeline: HistoryEvent[];
  movements: Array<{
    at: string;
    type: string;
    label: string;
    description: string;
    amount: number;
    status: string;
  }>;
}

const WALLET_TYPE_LABELS: Record<string, string> = {
  PAYMENT: 'Pago de la reserva',
  REFUND: 'Reembolso',
  EARNING: 'Ganancia del servicio',
  OVERTIME_FEE: 'Cobro por tiempo extra',
  OVERTIME_EARNING: 'Ganancia por tiempo extra',
  TIP: 'Propina',
  DONATION: 'Donación',
  DEBT_RECOVERY: 'Recuperación de deuda',
  COMMISSION: 'Comisión',
  FINE: 'Multa',
  GIFT: 'Crédito de regalo',
};

const CANCEL_SOURCE_LABELS: Record<string, string> = {
  CLIENT: 'el dueño',
  CAREGIVER: 'el cuidador',
  ADMIN: 'soporte',
  QR_ABANDONED: 'el sistema (QR sin pagar)',
  PAYMENT_TIMEOUT: 'el sistema (pago vencido)',
};

const EVENT_TITLES: Record<string, string> = {
  INCIDENT: 'Incidente reportado',
  ACCIDENT: 'Accidente reportado',
  ILLNESS: 'Problema de salud reportado',
  COMPLICATION: 'Complicación reportada',
  NOTE: 'Nota del cuidador',
  PHOTO: 'Foto del servicio',
  WALK_UPDATE: 'Actualización del paseo',
  INCIDENT_RESOLVED: 'Emergencia resuelta',
  CLIENT_SOS: 'Alerta SOS del dueño',
};

function iso(d: Date | string | null | undefined): string | null {
  if (!d) return null;
  return (d instanceof Date ? d : new Date(d)).toISOString();
}

function methodLabel(method: PaymentMethodCode, approvedBySupport: boolean): string {
  const base: Record<PaymentMethodCode, string> = {
    WALLET: 'Billetera Garden',
    QR: 'QR bancario',
    CARD: 'Tarjeta',
    WALLET_QR: 'Billetera + QR bancario',
    WALLET_CARD: 'Billetera + tarjeta',
    OTHER: 'Método no registrado',
    PENDING: 'Pendiente de pago',
  };
  return approvedBySupport ? `${base[method]} (aprobado por soporte)` : base[method];
}

export async function getBookingHistory(
  bookingId: string,
  userId: string,
  role?: string
): Promise<BookingHistory> {
  const booking = await prisma.booking.findUnique({
    where: { id: bookingId },
    include: {
      caregiver: { select: { userId: true } },
      dispute: true,
      review: { select: { createdAt: true, rating: true, isSystemGenerated: true } },
    },
  });
  if (!booking) throw new BookingNotFoundError(bookingId);

  const isClient = booking.clientId === userId;
  const isCaregiver = booking.caregiver.userId === userId;
  const isAdmin = role === 'ADMIN';
  if (!isClient && !isCaregiver && !isAdmin) {
    throw new ForbiddenError('No tienes acceso a esta reserva');
  }
  const viewerRole: BookingHistory['viewerRole'] = isAdmin ? 'ADMIN' : isClient ? 'CLIENT' : 'CAREGIVER';
  const seesCaregiverSide = viewerRole !== 'CLIENT';

  const [walletTxs, adminActions] = await Promise.all([
    prisma.walletTransaction.findMany({
      where: {
        bookingId,
        // Cada parte solo ve sus propios movimientos; admin ve todos.
        ...(isAdmin ? {} : { userId }),
      },
      orderBy: { createdAt: 'asc' },
    }),
    prisma.adminAction.findMany({
      where: { targetId: bookingId, actionType: { in: ['APPROVE_PAYMENT', 'APPROVE_PAYMENT_SECURE', 'REFUND_BOOKING'] } },
      orderBy: { createdAt: 'asc' },
      select: { actionType: true, createdAt: true },
    }),
  ]);

  // ── Pago ────────────────────────────────────────────────────────────────
  const total = Number(booking.totalAmount);
  const wallet = Number(booking.walletPaymentAmount ?? 0);
  const donation = Number(booking.donationAmount ?? 0);
  const approvedBySupport = adminActions.some((a) => a.actionType.startsWith('APPROVE_PAYMENT'));
  const hasCard = !!booking.stripePaymentIntentId;
  const hasQr = !!(booking.qrId || booking.sipQrId);
  const PAID_STATUSES = ['WAITING_CAREGIVER_APPROVAL', 'CONFIRMED', 'IN_PROGRESS', 'COMPLETED'];
  // Reservas viejas/de prueba pueden haber llegado a COMPLETED sin paidAt: igual ya pasaron por el pago.
  const paid = !!booking.paidAt || PAID_STATUSES.includes(booking.status);

  let method: PaymentMethodCode;
  if (!paid) method = 'PENDING';
  else if (hasCard) method = wallet > 0 ? 'WALLET_CARD' : 'CARD';
  else if (wallet >= total && wallet > 0) method = 'WALLET';
  else if (hasQr) method = wallet > 0 ? 'WALLET_QR' : 'QR';
  else method = wallet > 0 ? 'WALLET' : 'OTHER';

  const refundAmount = booking.refundAmount != null ? Number(booking.refundAmount) : null;
  let payStatus: BookingHistory['payment']['status'] = paid ? 'PAID' : 'PENDING';
  if (paid && refundAmount != null && refundAmount > 0 && booking.refundStatus === 'PROCESSED') {
    payStatus = refundAmount >= total ? 'REFUNDED' : 'PARTIALLY_REFUNDED';
  }

  const commission = Number(booking.commissionAmount);
  const tax = Number(booking.taxAmount ?? 0);
  const rawRef = booking.sipTransaccionId ?? booking.qrId ?? booking.stripePaymentIntentId ?? null;

  const payment: BookingHistory['payment'] = {
    method,
    methodLabel: methodLabel(method, approvedBySupport),
    status: payStatus,
    totalAmount: total,
    walletAmount: wallet,
    externalAmount: Math.max(0, total - wallet),
    donationAmount: donation,
    paidAt: iso(booking.paidAt),
    approvedBySupport,
    reference: rawRef ? String(rawRef).slice(-8) : null,
    refundAmount,
    refundStatus: booking.refundStatus ?? null,
  };
  if (seesCaregiverSide) {
    payment.caregiverNetAmount = total - commission - tax;
    payment.commissionAmount = commission;
    payment.taxAmount = tax;
  }

  // ── Línea de tiempo ─────────────────────────────────────────────────────
  const tl: HistoryEvent[] = [];
  const push = (at: Date | string | null | undefined, e: Omit<HistoryEvent, 'at'>) => {
    const t = iso(at);
    if (t) tl.push({ at: t, ...e });
  };

  push(booking.createdAt, { kind: 'CREATED', actor: 'CLIENTE', title: 'Reserva creada' });

  if (booking.paymentApprovalRequestedAt && !hasCard) {
    push(booking.paymentApprovalRequestedAt, { kind: 'PAYMENT_REQUESTED', actor: 'CLIENTE', title: 'Se solicitó el pago' });
  }

  if (booking.paidAt) {
    const parts: string[] = [];
    if (wallet > 0) parts.push(`Billetera Bs ${wallet.toFixed(2)}`);
    if (total - wallet > 0.005) {
      parts.push(`${hasCard ? 'Tarjeta' : hasQr ? 'QR' : 'Pago externo'} Bs ${(total - wallet).toFixed(2)}`);
    }
    push(booking.paidAt, {
      kind: 'PAID',
      actor: approvedBySupport ? 'SOPORTE' : 'CLIENTE',
      title: `Pago confirmado · ${payment.methodLabel}`,
      detail: parts.join(' + ') || null,
      amount: total,
    });
  }

  push(booking.enRouteAt, { kind: 'EN_ROUTE', actor: 'CUIDADOR', title: 'El cuidador va en camino' });
  push(booking.arrivedAt, { kind: 'ARRIVED', actor: 'CUIDADOR', title: 'El cuidador llegó' });
  push(booking.serviceStartedAt, { kind: 'STARTED', actor: 'CUIDADOR', title: 'Servicio iniciado' });

  const events = Array.isArray(booking.serviceEvents) ? (booking.serviceEvents as any[]) : [];
  for (const ev of events) {
    const at = ev?.timestamp;
    if (!at || typeof ev.type !== 'string') continue;
    if (ev.type === 'EXTENSION_CONFIRMED') {
      const extra = Number(ev.extraAmount ?? 0);
      const how = ev.method === 'wallet' ? 'billetera' : ev.method === 'qr' ? 'QR' : ev.method ?? null;
      const size = ev.additionalDays
        ? `${ev.additionalDays} noche${ev.additionalDays > 1 ? 's' : ''}`
        : ev.additionalMinutes ? `${ev.additionalMinutes} min` : '';
      push(at, {
        kind: 'EXTENSION',
        actor: 'CLIENTE',
        title: `Servicio extendido${size ? ` · ${size}` : ''}`,
        detail: how ? `Pagado con ${how}` : null,
        amount: extra || null,
      });
    } else if (ev.type === 'EXTENSION_PENDING_PAYMENT') {
      push(at, { kind: 'EXTENSION_REQUESTED', actor: 'CLIENTE', title: 'Extensión solicitada, pago pendiente' });
    } else if (EVENT_TITLES[ev.type]) {
      push(at, {
        kind: ev.type,
        actor: ev.type === 'CLIENT_SOS' ? 'CLIENTE' : 'CUIDADOR',
        title: EVENT_TITLES[ev.type]!,
        detail: typeof ev.description === 'string' ? ev.description : null,
      });
    } else if (ev.type === 'SERVICE_REMINDER' || String(ev.type).endsWith('_NOTIFIED')) {
      // ruido interno del ledger de recordatorios — no se muestra
    }
  }

  push(booking.clientMarkedEndAt, { kind: 'CLIENT_MARKED_END', actor: 'CLIENTE', title: 'El dueño marcó el servicio como terminado' });
  push(booking.serviceEndedAt, {
    kind: 'ENDED',
    actor: 'CUIDADOR',
    title: 'Servicio finalizado',
    detail: booking.overtimeMinutes > 0 ? `Tiempo extra: ${booking.overtimeMinutes} min` : null,
  });

  if (booking.cancelledAt) {
    const who = CANCEL_SOURCE_LABELS[booking.cancellationSource ?? ''] ?? null;
    push(booking.cancelledAt, {
      kind: 'CANCELLED',
      actor: booking.cancellationSource === 'CAREGIVER' ? 'CUIDADOR'
        : booking.cancellationSource === 'ADMIN' ? 'SOPORTE'
        : booking.cancellationSource === 'CLIENT' ? 'CLIENTE' : 'SISTEMA',
      title: who ? `Reserva cancelada por ${who}` : 'Reserva cancelada',
      detail: booking.cancellationReason ?? null,
    });
    if (refundAmount != null && refundAmount > 0 && booking.refundStatus !== 'REJECTED') {
      const refundTitle: Record<string, string> = {
        PROCESSED: 'Reembolso acreditado',
        APPROVED: 'Reembolso aprobado',
        PENDING_APPROVAL: 'Reembolso pendiente de aprobación',
      };
      push(booking.cancelledAt, {
        kind: 'REFUND',
        actor: 'SISTEMA',
        title: refundTitle[booking.refundStatus ?? ''] ?? 'Reembolso registrado',
        amount: refundAmount,
      });
    }
  }

  if (booking.ownerRatedAt) {
    push(booking.ownerRatedAt, {
      kind: 'RATED',
      actor: 'CLIENTE',
      title: booking.ownerRating ? `El dueño calificó ${booking.ownerRating}★` : 'El dueño calificó el servicio',
      detail: booking.ownerComment ?? null,
    });
  } else if (booking.review?.isSystemGenerated) {
    push(booking.review.createdAt, { kind: 'AUTO_RELEASE', actor: 'SISTEMA', title: 'Pago liberado automáticamente (sin calificación)' });
  }

  if (booking.dispute) {
    const d = booking.dispute;
    push(d.createdAt, { kind: 'DISPUTE_OPENED', actor: 'CLIENTE', title: 'Se abrió una disputa' });
    if (d.appealedAt) {
      push(d.appealedAt, {
        kind: 'DISPUTE_APPEALED',
        actor: d.appealedBy === 'CAREGIVER' ? 'CUIDADOR' : 'CLIENTE',
        title: 'Se apeló el veredicto',
      });
    }
    if (d.status === 'RESOLVED' || d.status === 'APPEALED') {
      const verdictLabel: Record<string, string> = {
        CLIENT_WINS: 'a favor del dueño',
        CAREGIVER_WINS: 'a favor del cuidador',
        PARTIAL: 'parcial',
      };
      push(d.updatedAt, {
        kind: 'DISPUTE_RESOLVED',
        actor: 'SISTEMA',
        title: `Disputa resuelta${d.aiVerdict && verdictLabel[d.aiVerdict] ? ` · ${verdictLabel[d.aiVerdict]}` : ''}`,
        detail: d.resolution ?? null,
      });
    }
    push(d.appealResolvedAt, {
      kind: 'APPEAL_RESOLVED',
      actor: 'SOPORTE',
      title: 'Apelación resuelta por el equipo de Garden',
    });
  }

  if (booking.payoutStatus && booking.payoutStatus !== 'PENDING' && seesCaregiverSide) {
    const earning = walletTxs.find((t) => t.type === 'EARNING');
    if (booking.payoutStatus === 'PAID' && earning) {
      push(earning.createdAt, { kind: 'PAYOUT', actor: 'SISTEMA', title: 'Pago liberado al cuidador', amount: Number(earning.amount) });
    }
  }

  tl.sort((a, b) => a.at.localeCompare(b.at));

  const movements = walletTxs.map((t) => ({
    at: t.createdAt.toISOString(),
    type: t.type,
    label: WALLET_TYPE_LABELS[t.type] ?? t.type,
    description: t.description,
    amount: Number(t.amount),
    status: t.status,
  }));

  return { bookingId, status: booking.status, viewerRole, payment, timeline: tl, movements };
}
