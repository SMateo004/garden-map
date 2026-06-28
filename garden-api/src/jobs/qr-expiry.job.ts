/**
 * Job de expiración de QR de pago.
 *
 * Corre cada minuto. Encuentra reservas PENDING_PAYMENT cuyo qrExpiresAt ya pasó
 * y las cancela como QR_ABANDONED, invalidando el QR en SIP primero.
 *
 * Orden estricto por seguridad financiera:
 *  1. disableQr(bookingId) → SIP invalida el QR. Si falla, NO cancelar (reintentar en el siguiente ciclo).
 *  2. Solo si SIP respondió OK → cancelar en DB con QR_ABANDONED.
 *
 * Esto garantiza que nunca se cancele una reserva dejando el QR activo en el banco.
 */

import cron from 'node-cron';
import { BookingStatus, RefundStatus } from '@prisma/client';
import prisma from '../config/database.js';
import * as sipService from '../services/sip.service.js';
import { env } from '../config/env.js';
import logger from '../shared/logger.js';

export function iniciarJobQrExpiry() {
    cron.schedule('* * * * *', async () => {
        await procesarQrsExpirados();
    });
    logger.info('[QR-EXPIRY JOB] Monitor de expiración de QR activo.');
}

export async function procesarQrsExpirados() {
    try {
        const now = new Date();

        // Buscar reservas PENDING_PAYMENT con QR expirado
        const expiradas = await prisma.booking.findMany({
            where: {
                status: BookingStatus.PENDING_PAYMENT,
                qrExpiresAt: { lt: now },
                qrId: { not: null },
            },
            select: {
                id: true,
                clientId: true,
                walletPaymentAmount: true,
                sipQrId: true,
            },
        });

        if (expiradas.length === 0) return;

        logger.info(`[QR-EXPIRY] ${expiradas.length} QR(s) expirados a procesar`);

        for (const booking of expiradas) {
            try {
                await _expirarQr(booking, now);
            } catch (err) {
                logger.error('[QR-EXPIRY] Error procesando booking', { bookingId: booking.id, err });
            }
        }
    } catch (err) {
        logger.error('[QR-EXPIRY] Job fallido', { err });
    }
}

async function _expirarQr(
    booking: { id: string; clientId: string; walletPaymentAmount: unknown; sipQrId: string | null },
    now: Date
): Promise<void> {
    // ── Capa 1: Invalidar QR en SIP PRIMERO ────────────────────────────────────
    // Solo intentamos si SIP está activo y el QR fue generado por SIP (tiene sipQrId).
    // Si SIP está desactivado (dev/CI), pasamos directo a cancelar en DB.
    if (env.SIP_ENABLED && booking.sipQrId) {
        try {
            await sipService.disableQr(booking.id);
            logger.info('[QR-EXPIRY] QR inhabilitado en SIP', { bookingId: booking.id });
        } catch (err) {
            // Si SIP falla, NO cancelamos en DB — el QR podría seguir activo en el banco.
            // El job lo reintentará en el próximo ciclo (1 min).
            logger.warn('[QR-EXPIRY] disableQr falló — reintentando en el próximo ciclo', {
                bookingId: booking.id,
                err,
            });
            return; // <-- salida intencional: no cancelar sin confirmación de SIP
        }
    }

    // ── Capa 2: Cancelar en DB (solo si SIP invalidó el QR o SIP está desactivado) ─
    const walletPaid = Number(booking.walletPaymentAmount ?? 0);

    await prisma.$transaction(async (tx) => {
        await tx.booking.update({
            where: {
                id: booking.id,
                // Guard contra race condition: solo actualizar si aún está PENDING_PAYMENT
                status: BookingStatus.PENDING_PAYMENT,
            },
            data: {
                status: BookingStatus.CANCELLED,
                cancelledAt: now,
                cancellationReason: 'QR de pago expirado sin pago confirmado',
                cancellationSource: 'QR_ABANDONED',
                refundAmount: 0,
                refundStatus: RefundStatus.REJECTED,
            },
        });

        // Si el cliente había usado billetera (pago mixto), reembolsar automáticamente
        if (walletPaid > 0) {
            const updatedUser = await tx.user.update({
                where: { id: booking.clientId },
                data: { balance: { increment: walletPaid } },
                select: { balance: true },
            });
            await tx.walletTransaction.create({
                data: {
                    userId: booking.clientId,
                    type: 'REFUND',
                    amount: walletPaid,
                    balance: Number(updatedUser.balance),
                    description: `Reembolso automático — QR expirado sin pago (reserva ${booking.id.slice(0, 8)})`,
                    bookingId: booking.id,
                    status: 'COMPLETED',
                },
            });
            logger.info('[QR-EXPIRY] Billetera reembolsada por QR abandonado', {
                bookingId: booking.id,
                walletPaid,
            });
        }
    });

    logger.info('[QR-EXPIRY] Reserva cancelada (QR_ABANDONED)', { bookingId: booking.id });
}
