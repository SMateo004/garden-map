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
 */
import prisma from '../../config/database.js';
import logger from '../../shared/logger.js';
import { getNumericSetting, invalidateSetting } from '../../utils/settings-cache.js';

export type PricedService = 'PASEO' | 'GUARDERIA' | 'HOSPEDAJE';
export const PRICED_SERVICES: readonly PricedService[] = ['PASEO', 'GUARDERIA', 'HOSPEDAJE'];
export type OverrideScope = PricedService | 'ALL';

export const DEFAULT_COMMISSION_PCT = 10;
export const DEFAULT_TAX_RATE_PCT = 16;
export const MAX_COMMISSION_PCT = 50;
export const MAX_TAX_RATE_PCT = 50;

/** AppSettings keys. */
export const SETTING_DEFAULT_COMMISSION = 'platformCommissionPct';
export const SETTING_TAX_RATE = 'taxRatePct';
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
  taxRatePct: number;
}

const TTL_MS = 15_000;
let _cache: { cfg: PricingConfig; ts: number } | null = null;

export function invalidatePricingConfig(): void {
  _cache = null;
  invalidateSetting(SETTING_DEFAULT_COMMISSION);
  invalidateSetting(SETTING_TAX_RATE);
  for (const k of Object.values(SETTING_SERVICE_COMMISSION)) invalidateSetting(k);
}

/** Lee un setting numérico opcional: null si no existe / no es número válido. */
async function optionalPct(key: string, max: number): Promise<number | null> {
  const NOT_SET = -1;
  const v = await getNumericSetting(key, NOT_SET);
  return v >= 0 && v <= max ? v : null;
}

type OverrideRow = { caregiverId: string; serviceType: string; pct: unknown };

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
  const [defaultRaw, taxRaw, paseo, guarderia, hospedaje, rows] = await Promise.all([
    getNumericSetting(SETTING_DEFAULT_COMMISSION, DEFAULT_COMMISSION_PCT),
    getNumericSetting(SETTING_TAX_RATE, DEFAULT_TAX_RATE_PCT),
    optionalPct(SETTING_SERVICE_COMMISSION.PASEO, MAX_COMMISSION_PCT),
    optionalPct(SETTING_SERVICE_COMMISSION.GUARDERIA, MAX_COMMISSION_PCT),
    optionalPct(SETTING_SERVICE_COMMISSION.HOSPEDAJE, MAX_COMMISSION_PCT),
    loadOverrides().then((r) => {
      overridesFailed = r === null;
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

  const cfg: PricingConfig = {
    defaultCommissionPct:
      defaultRaw >= 0 && defaultRaw <= MAX_COMMISSION_PCT ? defaultRaw : DEFAULT_COMMISSION_PCT,
    serviceCommissionPct,
    overrides,
    taxRatePct: taxRaw >= 0 && taxRaw <= MAX_TAX_RATE_PCT ? taxRaw : DEFAULT_TAX_RATE_PCT,
  };
  if (!overridesFailed) _cache = { cfg, ts: Date.now() };
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

/** Comisión como tasa (0.10 = 10 %) para un cuidador y servicio. */
export async function getCommissionRate(serviceType: string, caregiverId?: string | null): Promise<number> {
  const cfg = await getPricingConfig();
  return resolveCommissionPct(cfg, serviceType, caregiverId) / 100;
}

/** Tasa de impuestos como fracción (0.16 = 16 %). */
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

/** Calcula lo que paga el cliente por un monto base del cuidador. Enteros en Bs. */
export function computeClientCharge(base: number, commissionRate: number, taxRate: number): ClientCharge {
  const b = Math.round(base);
  const priced = Math.round(b * (1 + commissionRate));
  const commission = priced - b;
  const tax = Math.round(priced * taxRate);
  return { base: b, priced, commission, tax, total: priced + tax };
}

/** Precio unitario del cuidador a partir del precio unitario con comisión guardado en la reserva. */
export function caregiverUnitFromPriced(pricedUnit: number, commissionRate: number): number {
  return Math.round(pricedUnit / (1 + commissionRate));
}

/** Monto neto del cuidador de una reserva ya guardada: total − comisión − impuestos. */
export function caregiverNetOf(b: {
  totalAmount: unknown;
  commissionAmount: unknown;
  taxAmount?: unknown;
}): number {
  return Number(b.totalAmount) - Number(b.commissionAmount) - Number(b.taxAmount ?? 0);
}
