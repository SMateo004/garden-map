/**
 * Facturación con NIT — interruptor de Admin > Comisiones / Finanzas (AppSettings `invoicingEnabled`).
 *
 * GARDEN todavía no emite facturas electrónicas ante el SIN (falta integrar un facturador
 * autorizado, SIAT). Mientras el admin no lo active, la app muestra "Datos de facturación" como
 * "Pronto" antes de pagar, no pide NIT y el backend ignora el que llegue (la reserva guarda "0").
 * Al activarlo vuelve el comportamiento de siempre: el NIT se pide, se guarda en la reserva y se
 * pre-carga en el perfil.
 */
import { getBoolSetting, invalidateSetting } from '../../utils/settings-cache.js';

export const SETTING_INVOICING_ENABLED = 'invoicingEnabled';

export async function isInvoicingEnabled(): Promise<boolean> {
  return getBoolSetting(SETTING_INVOICING_ENABLED, false);
}

export function invalidateInvoicingSetting(): void {
  invalidateSetting(SETTING_INVOICING_ENABLED);
}
