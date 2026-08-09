import prisma from '../../config/database.js';
import { BadRequestError, NotFoundError } from '../../shared/errors.js';
import logger from '../../shared/logger.js';
import type { CreatePromoCodeBody } from './promo-code.validation.js';

/** Aplica un código promocional a una reserva PENDING_PAYMENT — reduce
 * Booking.totalAmount DIRECTAMENTE, antes de que el cliente presione
 * "Generar QR" / pagar con billetera. initPayment() y el resto del motor
 * de pago no se tocan: simplemente ven un totalAmount ya descontado, como
 * si el cuidador hubiera cobrado menos desde el principio. */
export async function applyPromoCode(bookingId: string, clientId: string, code: string) {
  return prisma.$transaction(async (tx) => {
    const booking = await tx.booking.findFirst({ where: { id: bookingId, clientId } });
    if (!booking) throw new NotFoundError('Reserva no encontrada');
    if (booking.status !== 'PENDING_PAYMENT') {
      throw new BadRequestError('Solo se puede aplicar un código antes de pagar', 'BOOKING_NOT_PENDING');
    }
    if (booking.promoCode) {
      throw new BadRequestError('Ya aplicaste un código en esta reserva', 'PROMO_ALREADY_APPLIED');
    }

    const promo = await tx.promoCode.findUnique({ where: { code } });
    if (!promo || !promo.active) throw new NotFoundError('Código promocional no encontrado o inactivo');
    if (promo.expiresAt && promo.expiresAt < new Date()) {
      throw new BadRequestError('Este código promocional ya venció', 'PROMO_EXPIRED');
    }
    if (promo.maxUses != null && promo.usedCount >= promo.maxUses) {
      throw new BadRequestError('Este código promocional ya alcanzó su límite de usos', 'PROMO_LIMIT_REACHED');
    }
    if (promo.firstBookingOnly) {
      const completedCount = await tx.booking.count({ where: { clientId, status: 'COMPLETED' } });
      if (completedCount > 0) {
        throw new BadRequestError('Este código es solo para tu primera reserva', 'PROMO_FIRST_BOOKING_ONLY');
      }
    }

    const totalAmount = Number(booking.totalAmount);
    const commissionAmount = Number(booking.commissionAmount);
    const rawDiscount = promo.discountType === 'PERCENT'
      ? totalAmount * (Number(promo.discountValue) / 100)
      : Number(promo.discountValue);
    const discount = Math.min(Math.round(rawDiscount * 100) / 100, totalAmount);
    const newTotal = Math.max(0, Math.round((totalAmount - discount) * 100) / 100);

    // El descuento sale del margen de Garden, NUNCA del cuidador — se
    // resta lo mismo de commissionAmount (piso 0), así que lo que cobra el
    // cuidador (totalAmount - commissionAmount) queda igual que antes del
    // promo. Solo si el descuento supera la comisión completa de esta
    // reserva el excedente sí le toca al cuidador (caso límite: un promo
    // configurado más grande que el margen entero de Garden ahí) — se
    // loguea como warning para que un admin lo note. (Bug real encontrado
    // y corregido a pedido del usuario — antes SIEMPRE salía del cuidador.)
    const newCommission = Math.max(0, Math.round((commissionAmount - discount) * 100) / 100);
    if (discount > commissionAmount) {
      logger.warn('Promo supera la comisión completa de la reserva — el cuidador cobra menos', {
        bookingId, code, discount, commissionAmount,
      });
    }

    // Atomic claim del cupo — evita que dos requests casi simultáneos
    // (doble tap) dejen usedCount por debajo de lo real o pasen el límite.
    const claimed = await tx.promoCode.updateMany({
      where: { id: promo.id, ...(promo.maxUses != null ? { usedCount: { lt: promo.maxUses } } : {}) },
      data: { usedCount: { increment: 1 } },
    });
    if (claimed.count === 0) {
      throw new BadRequestError('Este código promocional ya alcanzó su límite de usos', 'PROMO_LIMIT_REACHED');
    }

    const updated = await tx.booking.update({
      where: { id: bookingId },
      data: {
        promoCode: code,
        promoDiscountAmount: discount,
        totalAmount: newTotal,
        commissionAmount: newCommission,
        // Snapshot de la comisión "de lista" antes del descuento — el libro
        // contable reconoce el ingreso completo y registra la diferencia
        // como gasto de marketing explícito, en vez de netearla en silencio.
        commissionAmountBeforePromo: commissionAmount,
      },
      select: { totalAmount: true, promoDiscountAmount: true },
    });

    logger.info('Código promocional aplicado', { bookingId, clientId, code, discount });
    return { totalAmount: Number(updated.totalAmount), discountAmount: Number(updated.promoDiscountAmount) };
  });
}

export async function createPromoCode(body: CreatePromoCodeBody) {
  return prisma.promoCode.create({
    data: {
      code: body.code,
      discountType: body.discountType,
      discountValue: body.discountValue,
      maxUses: body.maxUses,
      firstBookingOnly: body.firstBookingOnly,
      expiresAt: body.expiresAt ? new Date(body.expiresAt) : null,
    },
  });
}

export async function listPromoCodes() {
  return prisma.promoCode.findMany({ orderBy: { createdAt: 'desc' } });
}
