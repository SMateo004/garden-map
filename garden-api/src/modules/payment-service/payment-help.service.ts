/**
 * Ayuda con el pago por QR — el botón de soporte de la pantalla del QR.
 *
 * El cliente elige qué le pasa y el sistema lo resuelve en el momento cuando
 * se puede, sin esperar a una persona:
 *   - QR_NOT_WORKING     → su banco no lee el QR: se le muestra el QR sin monto
 *                          (el genérico del tipo de servicio que sube el admin)
 *                          para que escriba el monto a mano.
 *   - MORE_TIME          → se le acaba el tiempo: se renueva la vigencia del QR.
 *   - PAID_NOT_CONFIRMED → ya pagó y no se confirma: la app avisa el pago
 *                          ("Ya realicé el pago") y el equipo lo verifica.
 *   - WRONG_AMOUNT       → pagó otro monto: igual que el anterior, y el equipo
 *                          revisa la diferencia (si llegó menos, se cobra de la
 *                          billetera: payment-review.service.ts INCOMPLETE).
 *   - CANCEL             → quiere cancelar: la app cancela (sin costo, lo que se
 *                          descontó de la billetera vuelve).
 *   - OTHER              → otro problema: se deriva a un asesor.
 *
 * Siempre queda registrado en su chat de soporte (su mensaje y la respuesta
 * del bot con lo que se hizo) y se avisa a los admins, así nadie pierde el
 * hilo aunque el bot lo haya resuelto solo. El pago lo sigue aprobando el admin.
 */
import { BookingStatus } from '@prisma/client';
import prisma from '../../config/database.js';
import logger from '../../shared/logger.js';
import { BadRequestError, NotFoundError } from '../../shared/errors.js';
import { notifyAdmins } from '../../services/firebase.service.js';
import { getNumericSetting } from '../../utils/settings-cache.js';
import * as paymentQrService from '../../services/payment-qr.service.js';
import { recordSupportExchange } from '../support-chat/support-chat.service.js';
import { amountExpectedByQr } from './payment-review.service.js';

export const PAYMENT_HELP_ISSUES = [
  'QR_NOT_WORKING',
  'MORE_TIME',
  'PAID_NOT_CONFIRMED',
  'WRONG_AMOUNT',
  'CANCEL',
  'OTHER',
] as const;
export type PaymentHelpIssue = (typeof PAYMENT_HELP_ISSUES)[number];

/** Qué hace la app con la respuesta. */
export type PaymentHelpAction = 'SHOW_FALLBACK_QR' | 'EXTEND_QR' | 'DECLARE' | 'CANCEL' | 'OPEN_SUPPORT';

const ISSUE_LABEL: Record<PaymentHelpIssue, string> = {
  QR_NOT_WORKING: 'Mi banco no lee el QR',
  MORE_TIME: 'Necesito más tiempo para pagar',
  PAID_NOT_CONFIRMED: 'Ya pagué y no se confirma',
  WRONG_AMOUNT: 'Pagué un monto distinto',
  CANCEL: 'Quiero cancelar la reserva',
  OTHER: 'Tengo otro problema con el pago',
};

const bs = (n: number) => `Bs ${n.toFixed(2)}`;

export async function requestPaymentHelp(params: {
  bookingId: string;
  clientId: string;
  issue: PaymentHelpIssue;
  /** WRONG_AMOUNT: cuánto dice que pagó. */
  paidAmount?: number;
  /** OTHER: lo que cuenta. */
  detail?: string;
}): Promise<{ action: PaymentHelpAction; message: string; fallbackQrUrl?: string; qrExpiresAt?: string }> {
  const { bookingId, clientId, issue, paidAmount } = params;
  const detail = params.detail?.trim().slice(0, 500);

  const booking = await prisma.booking.findFirst({
    where: { id: bookingId, clientId },
    select: {
      id: true,
      status: true,
      serviceType: true,
      qrExpiresAt: true,
      totalAmount: true,
      walletPaymentAmount: true,
      donationAmount: true,
      paymentExpectedAmount: true,
    },
  });
  if (!booking) throw new NotFoundError('Reserva no encontrada');
  if (booking.status !== BookingStatus.PENDING_PAYMENT && booking.status !== BookingStatus.PAYMENT_PENDING_APPROVAL) {
    throw new BadRequestError('Esta reserva ya no tiene un pago pendiente.', 'NOT_PAYING');
  }

  const ref = booking.id.slice(0, 8).toUpperCase();
  const expected = amountExpectedByQr(booking);
  let action: PaymentHelpAction;
  let message: string;
  let escalate = false;
  let fallbackQrUrl: string | undefined;
  let qrExpiresAt: string | undefined;

  switch (issue) {
    case 'QR_NOT_WORKING': {
      fallbackQrUrl = (await paymentQrService.getPaymentQrImageUrl(booking.serviceType)) ?? undefined;
      if (fallbackQrUrl) {
        action = 'SHOW_FALLBACK_QR';
        message =
          `Te mostramos otro QR, sin monto. Escanéalo con tu banco y escribe a mano ${bs(expected)}. ` +
          'Cuando termines, toca "Ya realicé el pago" y lo verificamos.';
      } else {
        action = 'OPEN_SUPPORT';
        escalate = true;
        message = 'No tenemos un QR alternativo en este momento. Ya avisamos a un asesor: te escribe aquí en unos minutos.';
      }
      break;
    }
    case 'MORE_TIME': {
      if (booking.status !== BookingStatus.PENDING_PAYMENT) {
        action = 'DECLARE';
        message = 'Tu pago ya está en verificación: la reserva no se cancela mientras tanto.';
        break;
      }
      const minutes = await getNumericSetting('qrValidityMinutes', 15);
      const newExpiry = new Date(Date.now() + minutes * 60_000);
      // Solo extender, nunca acortar; y solo si el QR sigue vigente (si ya
      // venció, qr-expiry.job.ts pudo haber cancelado la reserva).
      const extended = await prisma.booking.updateMany({
        where: {
          id: booking.id,
          status: BookingStatus.PENDING_PAYMENT,
          qrExpiresAt: { gt: new Date(), lt: newExpiry },
        },
        data: { qrExpiresAt: newExpiry },
      });
      if (extended.count === 0 && !(booking.qrExpiresAt && booking.qrExpiresAt >= newExpiry)) {
        action = 'OPEN_SUPPORT';
        escalate = true;
        message = 'Tu código ya venció. Ya avisamos a un asesor para ayudarte a terminar el pago.';
        break;
      }
      action = 'EXTEND_QR';
      qrExpiresAt = (extended.count > 0 ? newExpiry : booking.qrExpiresAt!).toISOString();
      message = `Listo: tienes ${minutes} minutos más para pagar con el mismo QR.`;
      break;
    }
    case 'PAID_NOT_CONFIRMED':
      action = 'DECLARE';
      message =
        'Avisamos a nuestro equipo para verificar tu pago. Tu reserva no se cancela mientras tanto; ' +
        'te confirmamos apenas lo veamos.';
      break;
    case 'WRONG_AMOUNT':
      action = 'DECLARE';
      escalate = true;
      message =
        `Avisamos al equipo para revisar tu pago (debía ser ${bs(expected)}). ` +
        'Si llegó menos, la diferencia se descuenta de tu billetera GARDEN; si llegó de más, un asesor te escribe para devolverte el excedente.';
      break;
    case 'CANCEL':
      action = 'CANCEL';
      message = 'Puedes cancelar sin costo mientras no hayas pagado. Si se descontó algo de tu billetera, vuelve a ella.';
      break;
    default:
      action = 'OPEN_SUPPORT';
      escalate = true;
      message = 'Ya avisamos a un asesor. Cuéntanos aquí qué pasó y te ayudamos a terminar el pago.';
  }

  const clientText =
    `[Ayuda con el pago · reserva ${ref}] ${ISSUE_LABEL[issue]}` +
    (issue === 'WRONG_AMOUNT' && paidAmount != null ? ` — dice que pagó ${bs(paidAmount)} (debía ${bs(expected)})` : '') +
    (detail ? ` — "${detail}"` : '');

  try {
    await recordSupportExchange(clientId, clientText, message, { escalate });
  } catch (err) {
    logger.error('[PaymentHelp] No se pudo registrar en el chat de soporte', { bookingId, err });
  }
  notifyAdmins(
    escalate ? '🆘 Ayuda con un pago' : 'Ayuda con un pago',
    `Reserva ${ref}: ${ISSUE_LABEL[issue]}${issue === 'WRONG_AMOUNT' && paidAmount != null ? ` (pagó ${bs(paidAmount)} de ${bs(expected)})` : ''}. ${escalate ? 'Necesita un asesor.' : 'El bot ya lo atendió.'}`,
    { type: 'ADMIN_PAYMENT_HELP', bookingId: booking.id }
  ).catch(() => {});

  logger.info('[PaymentHelp] Pedido de ayuda con el pago', { bookingId, issue, action, escalate });
  return { action, message, fallbackQrUrl, qrExpiresAt };
}
