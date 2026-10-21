/**
 * Precios al cliente: comisión variable de GARDEN + impuestos.
 *
 * Modelo (decidido con el founder, 2026-10-03):
 *   base         = precio del cuidador (lo que él cobra)
 *   comisionado  = round(base × (1 + comisión))   ← la comisión NO se muestra al cliente
 *   impuesto     = round(comisionado × tasa)      ← IVA 13% + IT 3% = 16% sobre TODO lo que cobra GARDEN
 *   total        = comisionado + impuesto         ← Booking.totalAmount (lo que el cliente paga)
 *
 * Lo que recibe el cuidador no cambia: total − commissionAmount − taxAmount = base.
 * La comisión depende del servicio y, opcionalmente, del cuidador/empresa:
 *   override del cuidador para ese servicio  >  override 'ALL' del cuidador
 *   >  comisión global del servicio (AppSettings commissionPct<Servicio>)
 *   >  comisión global por defecto (AppSettings platformCommissionPct, 10).
 * Todo se edita desde Admin (ver admin.pricing.*). Todos los montos son enteros en Bs,
 * como el resto del sistema (los QR por monto exacto se indexan por boliviano).
 *
 * QUIÉN PAGA LA COMISIÓN (desde 2026-10-21): cada cuidador/empresa elige
 * (CaregiverProfile.commissionPaidBy). 'CLIENT' es el modelo de arriba. 'CAREGIVER':
 *   comisionado = base (el dueño ve el precio del cuidador, sin recargo)
 *   comisión    = round(base × comisión)          ← se descuenta de lo que cobra el cuidador
 *   impuesto    = round(base × tasa);  total = base + impuesto
 * caregiverNetOf() (total − comisión − impuestos) da base − comisión: no cambia nada
 * aguas abajo (liberación de pago, disputas, reembolsos). Cada reserva guarda una copia
 * (Booking.commissionPaidBy): cambiar la opción no toca reservas existentes.
 *
 * IMPUESTOS EN PAUSA (desde 2026-10-07): el impuesto solo se cobra si el admin lo aprobó
 * con el interruptor de Admin > Comisiones / Finanzas (AppSettings taxesEnabled). Es la ÚNICA
 * condición — no depende de SIP_ENABLED ni de ninguna otra variable de entorno. Mientras no
 * esté aprobado, la tasa EFECTIVA es 0: no se suma impuesto, no se guarda taxAmount y la app
 * no los menciona. `taxRatePct` de PricingConfig es siempre la efectiva; la tasa configurada
 * (16) queda en `configuredTaxRatePct` para cuando se apruebe.
 */
import prisma from '../../config/database.js';
import logger from '../../shared/logger.js';
import { getBoolSetting, getNumericSetting, invalidateSetting } from '../../utils/settings-cache.js';

export type PricedService = 'PASEO' | 'GUARDERIA' | 'HOSPEDAJE';
export const PRICED_SERVICES: readonly PricedService[] = ['PASEO', 'GUARDERIA', 'HOSPEDAJE'];
export type OverrideScope = PricedService | 'ALL';

/** Quién paga la comisión de GARDEN. Cualquier otro valor se trata como 'CLIENT'. */
export type CommissionPayer = 'CLIENT' | 'CAREGIVER';
export function normalizePayer(v: unknown): CommissionPayer {
  return v === 'CAREGIVER' ? 'CAREGIVER' : 'CLIENT';
}

export const DEFAULT_COMMISSION_PCT = 10;
export const DEFAULT_TAX_RATE_PCT = 16;
export const MAX_COMMISSION_PCT = 50;
export const MAX_TAX_RATE_PCT = 50;

/** AppSettings keys. */
export const SETTING_DEFAULT_COMMISSION = 'platformCommissionPct';
export const SETTING_TAX_RATE = 'taxRatePct';
/** Interruptor del admin para cobrar impuestos. Ausente = apagado. */
export const SETTING_TAXES_ENABLED = 'taxesEnabled';
export const SETTING_SERVICE_COMMISSION: Record<PricedService, string> = {
  PASEO: 'commissionPctPaseo',
  GUARDERIA: 'commissionPctGuarderia',
  HOSPEDAJE: 'commissionPctHospedaje',
};

export interface PricingConfig {
  defaultCommissionPct: number;
  /** Solo los servicios con comisión propia; el resto cae a defaultCommissionPct. */
  serviceCommissionPct: Partial<Record<PricedService, number>>;
  overrides: Map<string, Partial<Record<OverrideScope, number>>>;
  /** Cuidadores (CaregiverProfile.id) que pagan ellos la comisión: el dueño no ve recargo. */
  caregiverPaysCommission: Set<string>;
  /** Tasa EFECTIVA que se cobra hoy: 0 mientras los impuestos estén en pausa. */
  taxRatePct: number;
  /** Tasa configurada en Admin > Comisiones (IVA+IT), aplicada solo cuando taxesActive. */
  configuredTaxRatePct: number;
  /** El admin aprobó cobrar impuestos (el switch). */
  taxesEnabled: boolean;
  /** Se cobran hoy — igual a taxesEnabled; si es false no se cobra ni se menciona impuesto. */
  taxesActive: boolean;
}

const TTL_MS = 15_000;
let _cache: { cfg: PricingConfig; ts: number } | null = null;

export function invalidatePricingConfig(): void {
  _cache = null;
  invalidateSetting(SETTING_DEFAULT_COMMISSION);
  invalidateSetting(SETTING_TAX_RATE);
  invalidateSetting(SETTING_TAXES_ENABLED);
  for (const k of Object.values(SETTING_SERVICE_COMMISSION)) invalidateSetting(k);
}

/** Lee un setting numérico opcional: null si no existe / no es número válido. */
async function optionalPct(key: string, max: number): Promise<number | null> {
  const NOT_SET = -1;
  const v = await getNumericSetting(key, NOT_SET);
  return v >= 0 && v <= max ? v : null;
}

type OverrideRow = { caregiverId: string; serviceType: string; pct: unknown };

/** null si falla: se muestra el precio con recargo (caso por defecto) y no se cachea. */
async function loadCaregiverPayers(): Promise<string[] | null> {
  try {
    const rows = await prisma.caregiverProfile.findMany({
      where: { commissionPaidBy: 'CAREGIVER' },
      select: { id: true },
    });
    return rows.map((r) => r.id);
  } catch (err) {
    logger.error('[PRICING] no se pudo leer quién paga la comisión', { err });
    return null;
  }
}

/** null si falla: se cobra la comisión del servicio (mejor que dejar de reservar) y no se cachea. */
async function loadOverrides(): Promise<OverrideRow[] | null> {
  try {
    return await prisma.caregiverCommissionOverride.findMany({
      select: { caregiverId: true, serviceType: true, pct: true },
    });
  } catch (err) {
    logger.error('[PRICING] no se pudieron leer las comisiones personalizadas', { err });
    return null;
  }
}

export async function getPricingConfig(): Promise<PricingConfig> {
  if (_cache && Date.now() - _cache.ts < TTL_MS) return _cache.cfg;

  let overridesFailed = false;
  let payersFailed = false;
  const [defaultRaw, taxRaw, taxesEnabled, paseo, guarderia, hospedaje, rows, payers] = await Promise.all([
    getNumericSetting(SETTING_DEFAULT_COMMISSION, DEFAULT_COMMISSION_PCT),
    getNumericSetting(SETTING_TAX_RATE, DEFAULT_TAX_RATE_PCT),
    // Si la lectura falla, getBoolSetting devuelve el default (false): ante la duda NO se cobra impuesto.
    getBoolSetting(SETTING_TAXES_ENABLED, false),
    optionalPct(SETTING_SERVICE_COMMISSION.PASEO, MAX_COMMISSION_PCT),
    optionalPct(SETTING_SERVICE_COMMISSION.GUARDERIA, MAX_COMMISSION_PCT),
    optionalPct(SETTING_SERVICE_COMMISSION.HOSPEDAJE, MAX_COMMISSION_PCT),
    loadOverrides().then((r) => {
      overridesFailed = r === null;
      return r ?? [];
    }),
    loadCaregiverPayers().then((r) => {
      payersFailed = r === null;
      return r ?? [];
    }),
  ]);

  const serviceCommissionPct: PricingConfig['serviceCommissionPct'] = {};
  if (paseo !== null) serviceCommissionPct.PASEO = paseo;
  if (guarderia !== null) serviceCommissionPct.GUARDERIA = guarderia;
  if (hospedaje !== null) serviceCommissionPct.HOSPEDAJE = hospedaje;

  const overrides: PricingConfig['overrides'] = new Map();
  for (const r of rows) {
    if (r.serviceType !== 'ALL' && !PRICED_SERVICES.includes(r.serviceType as PricedService)) continue;
    const entry = overrides.get(r.caregiverId) ?? {};
    entry[r.serviceType as OverrideScope] = Number(r.pct);
    overrides.set(r.caregiverId, entry);
  }

  const configuredTaxRatePct = taxRaw >= 0 && taxRaw <= MAX_TAX_RATE_PCT ? taxRaw : DEFAULT_TAX_RATE_PCT;
  const taxesActive = taxesEnabled;
  const cfg: PricingConfig = {
    defaultCommissionPct:
      defaultRaw >= 0 && defaultRaw <= MAX_COMMISSION_PCT ? defaultRaw : DEFAULT_COMMISSION_PCT,
    serviceCommissionPct,
    overrides,
    caregiverPaysCommission: new Set(payers),
    taxRatePct: taxesActive ? configuredTaxRatePct : 0,
    configuredTaxRatePct,
    taxesEnabled,
    taxesActive,
  };
  if (!overridesFailed && !payersFailed) _cache = { cfg, ts: Date.now() };
  return cfg;
}

/** Comisión (%) aplicable a un cuidador para un servicio — función pura sobre la config. */
export function resolveCommissionPct(
  cfg: PricingConfig,
  serviceType: string,
  caregiverId?: string | null
): number {
  const svc = serviceType as PricedService;
  if (caregiverId) {
    const o = cfg.overrides.get(caregiverId);
    if (o) {
      if (o[svc] !== undefined) return o[svc]!;
      if (o.ALL !== undefined) return o.ALL;
    }
  }
  return cfg.serviceCommissionPct[svc] ?? cfg.defaultCommissionPct;
}

/**
 * Recargo (%) que ve el DUEÑO en listados y perfiles: la comisión, o 0 si ese cuidador
 * paga él la comisión. Solo para mostrar precios; la reserva usa computeClientCharge.
 */
export function clientMarkupPct(cfg: PricingConfig, serviceType: string, caregiverId?: string | null): number {
  if (caregiverId && cfg.caregiverPaysCommission.has(caregiverId)) return 0;
  return resolveCommissionPct(cfg, serviceType, caregiverId);
}

/** Comisión como tasa (0.10 = 10 %) para un cuidador y servicio. */
export async function getCommissionRate(serviceType: string, caregiverId?: string | null): Promise<number> {
  const cfg = await getPricingConfig();
  return resolveCommissionPct(cfg, serviceType, caregiverId) / 100;
}

/** Tasa de impuestos EFECTIVA como fracción (0.16 = 16 %; 0 mientras estén en pausa). */
export async function getTaxRate(): Promise<number> {
  return (await getPricingConfig()).taxRatePct / 100;
}

export interface ClientCharge {
  /** Precio del cuidador (sin comisión ni impuesto). */
  base: number;
  /** base + comisión (lo que el cliente ve como precio del servicio, antes de impuestos). */
  priced: number;
  commission: number;
  tax: number;
  /** priced + tax — Booking.totalAmount. */
  total: number;
}

/**
 * Calcula lo que paga el cliente por un monto base del cuidador. Enteros en Bs.
 * payer 'CAREGIVER': el dueño paga base + impuesto y la comisión se le descuenta al
 * cuidador (ver cabecera del archivo).
 */
export function computeClientCharge(
  base: number,
  commissionRate: number,
  taxRate: number,
  payer: CommissionPayer = 'CLIENT'
): ClientCharge {
  const b = Math.max(0, Math.round(base));
  const rate = Math.max(0, commissionRate);
  if (payer === 'CAREGIVER') {
    const commission = Math.round(b * rate);
    const tax = Math.round(b * taxRate);
    return { base: b, priced: b, commission, tax, total: b + tax };
  }
  const priced = Math.round(b * (1 + rate));
  const commission = priced - b;
  const tax = Math.round(priced * taxRate);
  return { base: b, priced, commission, tax, total: priced + tax };
}

/**
 * Precio unitario del cuidador a partir del precio unitario que vio el dueño (Booking.
 * pricePerUnit). Con payer 'CAREGIVER' no hubo recargo: son el mismo.
 */
export function caregiverUnitFromPriced(
  pricedUnit: number,
  commissionRate: number,
  payer: CommissionPayer = 'CLIENT'
): number {
  if (payer === 'CAREGIVER') return Math.round(pricedUnit);
  return Math.round(pricedUnit / (1 + commissionRate));
}

/**
 * Comisión que salió del bolsillo del DUEÑO en una reserva: la comisión completa si la
 * pagó él, 0 si la absorbió el cuidador. Para reembolsos que "retienen la comisión".
 */
export function clientPaidCommission(b: { commissionAmount: unknown; commissionPaidBy?: unknown }): number {
  return normalizePayer(b.commissionPaidBy) === 'CAREGIVER' ? 0 : Number(b.commissionAmount);
}

/**
 * Precio del cuidador (sin comisión) para un paseo de 30 minutos: el que él fijó en su perfil
 * (pricePerWalk30) o, si no lo cargó, la mitad del de 60 minutos. Es la ÚNICA regla: la usan la
 * reserva (lo que se cobra) y los listados/perfiles (lo que se muestra), así nunca divergen.
 * Antes la reserva siempre cobraba la mitad del de 60 aunque el cuidador hubiera fijado otro
 * precio, y el perfil mostraba el suyo.
 */
export function walk30BasePrice(pricePerWalk30: unknown, pricePerWalk60: unknown): number | null {
  const p30 = Number(pricePerWalk30 ?? 0);
  if (p30 > 0) return Math.round(p30);
  const p60 = Number(pricePerWalk60 ?? 0);
  return p60 > 0 ? Math.round(p60 / 2) : null;
}

/** Monto neto del cuidador de una reserva ya guardada: total − comisión − impuestos. */
export function caregiverNetOf(b: {
  totalAmount: unknown;
  commissionAmount: unknown;
  taxAmount?: unknown;
}): number {
  return Number(b.totalAmount) - Number(b.commissionAmount) - Number(b.taxAmount ?? 0);
}
