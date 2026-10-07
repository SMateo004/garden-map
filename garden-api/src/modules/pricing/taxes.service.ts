/**
 * Impuestos en pausa — qué pasa con las reservas que todavía no se pagaron.
 *
 * Mientras los impuestos estén en pausa (pricing.service.ts → taxesActive=false) ninguna
 * reserva nueva lleva impuesto. Pero una reserva creada ANTES de la pausa puede seguir
 * esperando pago con su taxAmount > 0: si no se corrige, el cliente pagaría un impuesto que
 * GARDEN ya no cobra. stripTaxFromUnpaidBooking() se lo quita:
 *
 *   totalAmount −= taxAmount;  taxAmount = 0
 *
 * La comisión y lo del cuidador (total − comisión − impuesto) no cambian. Solo se toca una
 * reserva que:
 *  - está en PENDING_MG o PENDING_PAYMENT (nada cobrado todavía), y
 *  - no tiene nada pagado con billetera (walletPaymentAmount = 0): si el cliente ya pagó una
 *    parte, el precio con el que empezó a pagar se respeta.
 * Si tenía un QR emitido, se borra (el próximo initPayment genera uno con el monto correcto)
 * y, si fue un QR del banco (SIP), se inhabilita allá para que nadie pague el monto viejo.
 *
 * Al ACTIVAR los impuestos no se agregan a reservas ya creadas: el precio que el cliente vio
 * al reservar se respeta; solo las reservas nuevas llevan impuesto.
 */
import { BookingStatus, Prisma } from '@prisma/client';
import prisma from '../../config/database.js';
import { env } from '../../config/env.js';
import logger from '../../shared/logger.js';
import * as sipService from '../../services/sip.service.js';
import { getPricingConfig } from './pricing.service.js';

export const UNPAID_STATUSES: BookingStatus[] = [BookingStatus.PENDING_MG, BookingStatus.PENDING_PAYMENT];

type Tx = Prisma.TransactionClient;

/**
 * Quita el impuesto de UNA reserva impaga, dentro de la transacción del llamador.
 * El UPDATE es condicional (estado, impuesto y billetera en el WHERE): si otra request ya la
 * pagó o la corrigió en paralelo, no hace nada. Devuelve el impuesto quitado (0 si no aplicó).
 */
export async function stripTaxFromUnpaidBooking(tx: Tx, bookingId: string): Promise<{ removed: number; hadSipQr: boolean }> {
  const b = await tx.booking.findUnique({
    where: { id: bookingId },
    select: { status: true, totalAmount: true, taxAmount: true, walletPaymentAmount: true, sipQrId: true },
  });
  if (!b) return { removed: 0, hadSipQr: false };
  const tax = Number(b.taxAmount ?? 0);
  if (tax <= 0 || !UNPAID_STATUSES.includes(b.status) || Number(b.walletPaymentAmount ?? 0) > 0) {
    return { removed: 0, hadSipQr: false };
  }
  const newTotal = Math.round((Number(b.totalAmount) - tax) * 100) / 100;
  if (newTotal < 0) return { removed: 0, hadSipQr: false }; // dato inconsistente: no se toca
  const res = await tx.booking.updateMany({
    where: {
      id: bookingId,
      status: { in: UNPAID_STATUSES },
      taxAmount: b.taxAmount,
      totalAmount: b.totalAmount,
      walletPaymentAmount: 0,
    },
    data: {
      totalAmount: new Prisma.Decimal(newTotal),
      taxAmount: new Prisma.Decimal(0),
      qrId: null,
      qrImageUrl: null,
      qrExpiresAt: null,
      sipQrId: null,
      sipTransaccionId: null,
    },
  });
  if (res.count === 0) return { removed: 0, hadSipQr: false };
  return { removed: tax, hadSipQr: !!b.sipQrId };
}

/** Inhabilita en el banco un QR emitido con el monto viejo. Nunca rompe al llamador. */
export function disableStaleSipQr(bookingId: string): void {
  if (!env.SIP_ENABLED) return; // sin SIP no hay QR del banco que inhabilitar
  sipService.disableQr(bookingId).catch((err) =>
    logger.warn('[TAXES] no se pudo inhabilitar el QR con impuesto en el banco', { bookingId, err })
  );
}

/**
 * Barrido: si los impuestos están en pausa, se los quita a todas las reservas impagas que
 * todavía los tienen. Idempotente (se corre al arrancar y al pausar desde el admin).
 */
export async function stripTaxFromAllUnpaidBookings(): Promise<{ bookings: number; totalRemoved: number }> {
  const cfg = await getPricingConfig();
  if (cfg.taxesActive) return { bookings: 0, totalRemoved: 0 };

  const candidates = await prisma.booking.findMany({
    where: { status: { in: UNPAID_STATUSES }, taxAmount: { gt: 0 }, walletPaymentAmount: 0 },
    select: { id: true },
  });
  let bookings = 0;
  let totalRemoved = 0;
  for (const { id } of candidates) {
    try {
      const r = await prisma.$transaction((tx) => stripTaxFromUnpaidBooking(tx, id));
      if (r.removed > 0) {
        bookings += 1;
        totalRemoved += r.removed;
        if (r.hadSipQr) disableStaleSipQr(id);
        logger.info('[TAXES] impuesto quitado de una reserva impaga (impuestos en pausa)', { bookingId: id, removed: r.removed });
      }
    } catch (err) {
      logger.error('[TAXES] no se pudo quitar el impuesto de una reserva impaga', { bookingId: id, err });
    }
  }
  return { bookings, totalRemoved: Math.round(totalRemoved * 100) / 100 };
}
