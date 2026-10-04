/**
 * Filtros de WalletTransaction compartidos por la billetera y el panel del
 * cuidador, para que "Ganado" / "Ganancias del mes" / "Pagado" sumen lo mismo
 * en todas partes.
 *
 * Propinas: hasta 2026-10-04 el débito del cliente y el crédito del cuidador
 * se guardaban ambos como 'TIP' (monto positivo). Desde entonces el crédito
 * es 'TIP_RECEIVED'; las filas viejas se distinguen por la descripción
 * ("Propina recibida — …" vs "Propina — …", ver tipBooking en booking.service.ts).
 */
const LEGACY_TIP_RECEIVED = { type: 'TIP', description: { startsWith: 'Propina recibida' } };

/** Lo que entra como ganancia: servicio, tiempo extra y propinas recibidas. */
export const EARNING_FILTERS = [
  { type: { in: ['EARNING', 'OVERTIME_EARNING', 'TIP_RECEIVED'] } },
  LEGACY_TIP_RECEIVED,
];

/** Lo que sale por servicios: pagos, tiempo extra y propinas dadas. */
export const SPENDING_FILTERS = [
  { type: { in: ['PAYMENT', 'WALLET_PAYMENT', 'OVERTIME_FEE'] } },
  { type: 'TIP', NOT: { description: { startsWith: 'Propina recibida' } } },
];
