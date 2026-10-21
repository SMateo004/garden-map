/**
 * Premium ("Destacado") y quién paga la comisión — lo que ordena el marketplace.
 *
 * PREMIUM: el cuidador/empresa elige de 1 a N semanas (tabla de precios del admin,
 * premium.pricing.ts) y paga por QR — mismo flujo que una reserva: QR → "ya realicé el
 * pago" → el admin aprueba o rechaza; si nadie lo revisa antes de que venza el QR se
 * aprueba solo y el admin puede marcarlo después como "no recibido" (se quita). Sin
 * billetera. Un admin también puede registrarlo presencialmente (efectivo, etc.).
 * Cada compra PAID cubre un período encadenado después del vigente
 * (CaregiverProfile.premiumUntil).
 *
 * ORDEN DEL MARKETPLACE (CaregiverProfile.listingBoost): 2 Premium vigente, 1 paga su
 * comisión (sin ninguna marca visible), 0 el resto. Se recalcula al activar, quitar o
 * vencer Premium y al cambiar quién paga la comisión.
 *
 * Toda escritura de dinero/estado bloquea la fila del perfil (FOR UPDATE) y cambia el
 * estado de la compra con un updateMany condicionado al estado esperado: un doble toque,
 * dos admins o el banco y un admin a la vez nunca activan dos veces la misma compra.
 */
import { Prisma } from '@prisma/client';
import prisma from '../../config/database.js';
import logger from '../../shared/logger.js';
import { AppError, BadRequestError, ForbiddenError, NotFoundError, UnauthorizedError } from '../../shared/errors.js';
import { getCache, delByPrefix } from '../../shared/cache.js';
import { getNumericSetting } from '../../utils/settings-cache.js';
import { env } from '../../config/env.js';
import { sendPushToUser, notifyAdmins } from '../../services/firebase.service.js';
import {
  invalidatePricingConfig,
  normalizePayer,
  getPricingConfig,
  resolveCommissionPct,
  PRICED_SERVICES,
  type CommissionPayer,
} from '../pricing/pricing.service.js';
import {
  validatePriceTable,
  priceForWeeks,
  maxWeeksOf,
  PremiumTableError,
  type PremiumPricePoint,
} from './premium.pricing.js';

const DAY_MS = 24 * 60 * 60 * 1000;
const WEEK_MS = 7 * DAY_MS;

export const PREMIUM_STATUS = {
  PENDING_PAYMENT: 'PENDING_PAYMENT',
  DECLARED: 'PAYMENT_PENDING_APPROVAL',
  PAID: 'PAID',
  REJECTED: 'REJECTED',
  EXPIRED: 'EXPIRED',
  CANCELLED: 'CANCELLED',
  REVOKED: 'REVOKED',
} as const;
const OPEN_STATUSES = [PREMIUM_STATUS.PENDING_PAYMENT, PREMIUM_STATUS.DECLARED];

/** Un QR sin "ya pagué" se da por abandonado recién después de este margen. */
const UNDECLARED_GRACE_MS = 30 * 60 * 1000;
/** Aviso previo al vencimiento del Premium. */
const REMINDER_BEFORE_MS = 3 * DAY_MS;
/** Dos registros presenciales del mismo perfil en este lapso = doble toque. */
const MANUAL_DUPLICATE_WINDOW_MS = 2 * 60 * 1000;
/** Tiempo mínimo entre cambios de quién paga la comisión (evita ir y venir). */
export const COMMISSION_PAYER_COOLDOWN_MS = 24 * 60 * 60 * 1000;
export const MANUAL_PAYMENT_KINDS = ['CASH', 'TRANSFER', 'OTHER'] as const;
export type ManualPaymentKind = (typeof MANUAL_PAYMENT_KINDS)[number];

// ── Ajustes (Admin > Comisiones > Premium) ────────────────────────────────────

const SETTING_ENABLED = 'premiumEnabled';
const SETTING_TABLE = 'premiumPriceTable';

export interface PremiumSettings {
  /** El cuidador puede comprarlo desde la app (el admin puede registrarlo igual). */
  enabled: boolean;
  priceTable: PremiumPricePoint[];
  maxWeeks: number;
}

let _settingsCache: { s: PremiumSettings; ts: number } | null = null;
const SETTINGS_TTL_MS = 15_000;

export async function getPremiumSettings(): Promise<PremiumSettings> {
  if (_settingsCache && Date.now() - _settingsCache.ts < SETTINGS_TTL_MS) return _settingsCache.s;
  const rows = await prisma.appSettings.findMany({ where: { key: { in: [SETTING_ENABLED, SETTING_TABLE] } } });
  const byKey = new Map(rows.map((r) => [r.key, r.value]));
  let priceTable: PremiumPricePoint[] = [];
  try {
    const raw = byKey.get(SETTING_TABLE);
    if (raw) priceTable = validatePriceTable(JSON.parse(raw));
  } catch (err) {
    // Una tabla guardada inválida (no debería pasar: se valida al guardar) deja Premium
    // sin precios — nunca se cobra con una tabla rota.
    logger.error('[PREMIUM] tabla de precios guardada inválida', { err });
    priceTable = [];
  }
  let enabled = false;
  try {
    enabled = JSON.parse(byKey.get(SETTING_ENABLED) ?? 'false') === true;
  } catch {
    enabled = false;
  }
  const s: PremiumSettings = { enabled: enabled && priceTable.length > 0, priceTable, maxWeeks: maxWeeksOf(priceTable) };
  _settingsCache = { s, ts: Date.now() };
  return s;
}

export async function updatePremiumSettings(
  input: { enabled: unknown; priceTable: unknown },
  adminId: string
): Promise<PremiumSettings> {
  if (typeof input.enabled !== 'boolean') throw new BadRequestError('Indica si Premium está activo.');
  let table: PremiumPricePoint[];
  try {
    table = validatePriceTable(input.priceTable);
  } catch (err) {
    if (err instanceof PremiumTableError) throw new BadRequestError(err.message, 'PREMIUM_PRICE_TABLE_INVALID');
    throw err;
  }
  await prisma.$transaction([
    prisma.appSettings.upsert({
      where: { key: SETTING_TABLE },
      update: { value: JSON.stringify(table), updatedBy: adminId },
      create: { key: SETTING_TABLE, value: JSON.stringify(table), updatedBy: adminId },
    }),
    prisma.appSettings.upsert({
      where: { key: SETTING_ENABLED },
      update: { value: JSON.stringify(input.enabled), updatedBy: adminId },
      create: { key: SETTING_ENABLED, value: JSON.stringify(input.enabled), updatedBy: adminId },
    }),
    prisma.adminAction.create({
      data: {
        adminId,
        actionType: 'PREMIUM_SETTINGS',
        targetId: 'premium',
        notes: `Premium ${input.enabled ? 'activo' : 'pausado'} · ${table.map((p) => `${p.weeks} sem = Bs ${p.price}`).join(', ')}`,
      },
    }),
  ]);
  _settingsCache = null;
  return getPremiumSettings();
}

/** Precio de [weeks] semanas con la tabla vigente; error claro si no se puede comprar. */
export function quoteOrThrow(settings: PremiumSettings, weeks: unknown): number {
  const w = Number(weeks);
  if (!Number.isInteger(w) || w < 1) throw new BadRequestError('Elige una duración en semanas (1 o más).');
  if (settings.priceTable.length === 0) {
    throw new BadRequestError('Premium todavía no tiene precios configurados.', 'PREMIUM_NOT_CONFIGURED');
  }
  if (w > settings.maxWeeks) {
    throw new BadRequestError(`La duración máxima es de ${settings.maxWeeks} semanas.`, 'PREMIUM_WEEKS_OUT_OF_RANGE');
  }
  const price = priceForWeeks(settings.priceTable, w);
  if (price === null || price <= 0) throw new BadRequestError('No hay un precio para esa duración.');
  return price;
}

// ── Orden del marketplace ────────────────────────────────────────────────────

function boostFor(p: { premiumUntil: Date | null; commissionPaidBy: string }, now = new Date()): number {
  if (p.premiumUntil && p.premiumUntil.getTime() > now.getTime()) return 2;
  return normalizePayer(p.commissionPaidBy) === 'CAREGIVER' ? 1 : 0;
}

async function invalidateListings(caregiverId: string): Promise<void> {
  try {
    await getCache().del(`caregivers:detail:${caregiverId}`);
    await delByPrefix('caregivers:list:');
  } catch (err) {
    logger.warn('[PREMIUM] no se pudo invalidar el cache de listados', { caregiverId, err });
  }
}

/**
 * Re-encadena los períodos de las compras PAID (en orden de pago) y deja premiumUntil y
 * listingBoost coherentes. Se usa al quitar una compra: cada una empieza cuando se pagó
 * o cuando termina la anterior (lo que sea más tarde), así las siguientes se corren
 * hacia adelante y el período quitado no queda "regalado".
 */
async function rechainAndRefresh(tx: Prisma.TransactionClient, caregiverId: string, now = new Date()): Promise<Date | null> {
  const paid = await tx.premiumPurchase.findMany({
    where: { caregiverId, status: PREMIUM_STATUS.PAID },
    orderBy: [{ paidAt: 'asc' }, { activatedFrom: 'asc' }],
    select: { id: true, weeks: true, paidAt: true, activatedFrom: true, activatedUntil: true },
  });
  let cursor: Date | null = null;
  for (const p of paid) {
    const ownStart = p.paidAt ?? p.activatedFrom ?? now;
    const start: Date = cursor && cursor.getTime() > ownStart.getTime() ? cursor : ownStart;
    const end: Date = new Date(start.getTime() + p.weeks * WEEK_MS);
    if (p.activatedFrom?.getTime() !== start.getTime() || p.activatedUntil?.getTime() !== end.getTime()) {
      await tx.premiumPurchase.update({ where: { id: p.id }, data: { activatedFrom: start, activatedUntil: end } });
    }
    cursor = end;
  }
  const profile = await tx.caregiverProfile.findUnique({ where: { id: caregiverId }, select: { commissionPaidBy: true } });
  const premiumUntil = cursor && cursor.getTime() > now.getTime() ? cursor : null;
  await tx.caregiverProfile.update({
    where: { id: caregiverId },
    data: {
      premiumUntil,
      listingBoost: boostFor({ premiumUntil, commissionPaidBy: profile?.commissionPaidBy ?? 'CLIENT' }, now),
    },
  });
  return premiumUntil;
}

/**
 * Activa una compra (PENDING_PAYMENT o declarada → PAID): su período empieza cuando
 * termina el Premium vigente (o ahora). Devuelve null si otro proceso ya la resolvió.
 */
async function activatePurchase(
  purchaseId: string,
  opts: { decidedBy: string | null; autoApproved?: boolean; fromStatuses?: string[] }
): Promise<{ caregiverId: string; userId: string; until: Date; weeks: number; amount: number } | null> {
  const fromStatuses = opts.fromStatuses ?? OPEN_STATUSES;
  return prisma.$transaction(async (tx) => {
    const purchase = await tx.premiumPurchase.findUnique({
      where: { id: purchaseId },
      select: { id: true, caregiverId: true, weeks: true, amount: true, status: true },
    });
    if (!purchase || !fromStatuses.includes(purchase.status)) return null;
    await tx.$queryRaw`SELECT id FROM "caregiver_profiles" WHERE id = ${purchase.caregiverId} FOR UPDATE`;
    const profile = await tx.caregiverProfile.findUnique({
      where: { id: purchase.caregiverId },
      select: { userId: true, premiumUntil: true, commissionPaidBy: true },
    });
    if (!profile) return null;
    const now = new Date();
    const start = profile.premiumUntil && profile.premiumUntil.getTime() > now.getTime() ? profile.premiumUntil : now;
    const until = new Date(start.getTime() + purchase.weeks * WEEK_MS);
    const claimed = await tx.premiumPurchase.updateMany({
      where: { id: purchaseId, status: { in: fromStatuses } },
      data: {
        status: PREMIUM_STATUS.PAID,
        paidAt: now,
        activatedFrom: start,
        activatedUntil: until,
        decidedBy: opts.decidedBy,
        ...(opts.autoApproved ? { autoApprovedAt: now } : {}),
      },
    });
    if (claimed.count === 0) return null;
    await tx.caregiverProfile.update({
      where: { id: purchase.caregiverId },
      data: { premiumUntil: until, premiumReminderSentAt: null, listingBoost: 2 },
    });
    return { caregiverId: purchase.caregiverId, userId: profile.userId, until, weeks: purchase.weeks, amount: Number(purchase.amount) };
  });
}

function fmtDate(d: Date): string {
  // Fecha de Bolivia (UTC-4 todo el año), dd/mm/aaaa.
  const b = new Date(d.getTime() - 4 * 60 * 60 * 1000);
  return `${String(b.getUTCDate()).padStart(2, '0')}/${String(b.getUTCMonth() + 1).padStart(2, '0')}/${b.getUTCFullYear()}`;
}

async function notifyCaregiver(userId: string, title: string, message: string, type: string): Promise<void> {
  try {
    await prisma.notification.create({ data: { userId, title, message, type } });
    sendPushToUser(userId, title, message, { type }).catch(() => {});
  } catch (err) {
    logger.warn('[PREMIUM] no se pudo avisar al cuidador', { userId, type, err });
  }
}

async function afterActivation(r: { caregiverId: string; userId: string; until: Date; weeks: number }): Promise<void> {
  await invalidateListings(r.caregiverId);
  await notifyCaregiver(
    r.userId,
    '⭐ Ya eres Premium',
    `Tu perfil aparece como Destacado y primero en el marketplace hasta el ${fmtDate(r.until)}.`,
    'PREMIUM_ACTIVE'
  );
}

// ── Perfil del cuidador (titular, no empleados) ─────────────────────────────

async function ownProfile(userId: string) {
  const profile = await prisma.caregiverProfile.findUnique({
    where: { userId },
    select: {
      id: true, status: true, suspended: true, premiumUntil: true, commissionPaidBy: true,
      commissionPaidByChangedAt: true, isCompany: true,
    },
  });
  if (!profile) throw new ForbiddenError('Solo el titular del perfil de cuidador o empresa puede hacer esto.');
  return profile;
}

function purchaseView(p: any) {
  return {
    id: p.id,
    weeks: p.weeks,
    amount: Number(p.amount),
    status: p.status,
    method: p.method,
    manualPaymentKind: p.manualPaymentKind ?? null,
    qrImageUrl: OPEN_STATUSES.includes(p.status) ? p.qrImageUrl ?? null : null,
    qrExpiresAt: p.qrExpiresAt?.toISOString() ?? null,
    paymentDeclaredAt: p.paymentDeclaredAt?.toISOString() ?? null,
    paidAt: p.paidAt?.toISOString() ?? null,
    activatedFrom: p.activatedFrom?.toISOString() ?? null,
    activatedUntil: p.activatedUntil?.toISOString() ?? null,
    createdAt: p.createdAt.toISOString(),
  };
}

/** GET /api/caregiver/premium — estado, precios y compras del cuidador. */
export async function getMyPremium(userId: string) {
  const profile = await ownProfile(userId);
  const settings = await getPremiumSettings();
  const purchases = await prisma.premiumPurchase.findMany({
    where: { caregiverId: profile.id },
    orderBy: { createdAt: 'desc' },
    take: 30,
  });
  const now = Date.now();
  const open = purchases.find(
    (p) =>
      p.status === PREMIUM_STATUS.DECLARED ||
      (p.status === PREMIUM_STATUS.PENDING_PAYMENT && (!p.qrExpiresAt || p.qrExpiresAt.getTime() > now))
  );
  return {
    enabled: settings.enabled,
    priceTable: settings.priceTable,
    maxWeeks: settings.maxWeeks,
    active: !!profile.premiumUntil && profile.premiumUntil.getTime() > now,
    premiumUntil: profile.premiumUntil?.toISOString() ?? null,
    canBuy: settings.enabled && profile.status === 'APPROVED' && !profile.suspended,
    openPurchase: open ? purchaseView(open) : null,
    history: purchases.filter((p) => p !== open).map(purchaseView),
  };
}

/** QR para una compra: banco (SIP) si está activo; si no, el QR que subió el admin. */
async function qrForPurchase(purchaseId: string, amount: number): Promise<{
  qrId: string; qrImageUrl: string; qrExpiresAt: Date; sipQrId?: string;
}> {
  const minutes = await getNumericSetting('qrValidityMinutes', 15);
  const validity = minutes > 0 && minutes <= 24 * 60 ? minutes : 15;
  const { generateQR } = await import('../booking-service/booking.service.js');
  const qr = await generateQR(purchaseId, validity, amount);
  if (qr.qrImageType !== 'generated') {
    return { qrId: qr.qrId, qrImageUrl: qr.qrImageUrl, qrExpiresAt: qr.qrExpiresAt, sipQrId: (qr as any).sipQrId };
  }
  // Sin QR por monto exacto ni banco: cualquier QR de cuenta que haya subido el admin
  // (Admin > QR de pago) sirve — el monto lo ve el cuidador en pantalla.
  const { getAllPaymentQrImageUrls } = await import('../../services/payment-qr.service.js');
  const generic = Object.values(await getAllPaymentQrImageUrls()).find((u) => !!u);
  if (generic) return { qrId: qr.qrId, qrImageUrl: generic, qrExpiresAt: qr.qrExpiresAt };
  if (env.NODE_ENV === 'production') {
    throw new AppError(
      'El pago por QR no está disponible en este momento. Escríbenos a soporte para activar Premium.',
      503,
      'PREMIUM_QR_UNAVAILABLE'
    );
  }
  return { qrId: qr.qrId, qrImageUrl: qr.qrImageUrl, qrExpiresAt: qr.qrExpiresAt };
}

/**
 * POST /api/caregiver/premium/purchases — el cuidador elige la duración y recibe el QR.
 * Si ya tenía un QR sin pagar, se reemplaza (cambió de idea sobre la duración). Si ya
 * avisó que pagó, no puede iniciar otra compra hasta que se resuelva.
 */
export async function startPurchase(userId: string, weeks: unknown) {
  const profile = await ownProfile(userId);
  if (profile.status !== 'APPROVED' || profile.suspended) {
    throw new ForbiddenError('Tu perfil debe estar aprobado y activo para hacerte Premium.');
  }
  const settings = await getPremiumSettings();
  if (!settings.enabled) throw new BadRequestError('Premium no está disponible por ahora.', 'PREMIUM_DISABLED');
  const amount = quoteOrThrow(settings, weeks);
  const w = Number(weeks);

  const purchase = await prisma.$transaction(async (tx) => {
    await tx.$queryRaw`SELECT id FROM "caregiver_profiles" WHERE id = ${profile.id} FOR UPDATE`;
    const declared = await tx.premiumPurchase.count({
      where: { caregiverId: profile.id, status: PREMIUM_STATUS.DECLARED },
    });
    if (declared > 0) {
      throw new BadRequestError('Ya avisaste un pago que estamos revisando. Espera a que se confirme.', 'PREMIUM_PAYMENT_IN_REVIEW');
    }
    await tx.premiumPurchase.updateMany({
      where: { caregiverId: profile.id, status: PREMIUM_STATUS.PENDING_PAYMENT },
      data: { status: PREMIUM_STATUS.CANCELLED },
    });
    return tx.premiumPurchase.create({
      data: { caregiverId: profile.id, weeks: w, amount: new Prisma.Decimal(amount), method: 'QR' },
    });
  });

  let qr;
  try {
    qr = await qrForPurchase(purchase.id, amount);
  } catch (err) {
    await prisma.premiumPurchase.updateMany({
      where: { id: purchase.id, status: PREMIUM_STATUS.PENDING_PAYMENT },
      data: { status: PREMIUM_STATUS.CANCELLED },
    });
    throw err;
  }
  const updated = await prisma.premiumPurchase.update({
    where: { id: purchase.id },
    data: { qrId: qr.qrId, qrImageUrl: qr.qrImageUrl, qrExpiresAt: qr.qrExpiresAt, sipQrId: qr.sipQrId ?? null },
  });
  logger.info('[PREMIUM] QR generado', { caregiverId: profile.id, purchaseId: purchase.id, weeks: w, amount });
  return purchaseView(updated);
}

/** POST /api/caregiver/premium/purchases/:id/declared — "Ya realicé el pago". */
export async function declarePayment(userId: string, purchaseId: string) {
  const profile = await ownProfile(userId);
  const purchase = await prisma.premiumPurchase.findFirst({ where: { id: purchaseId, caregiverId: profile.id } });
  if (!purchase) throw new NotFoundError('Compra no encontrada');
  if (purchase.status === PREMIUM_STATUS.DECLARED) return purchaseView(purchase); // doble toque
  if (purchase.status !== PREMIUM_STATUS.PENDING_PAYMENT) {
    throw new BadRequestError('Este pago ya no está pendiente. Genera un QR nuevo.', 'PREMIUM_NOT_PENDING');
  }
  if (purchase.qrExpiresAt && purchase.qrExpiresAt.getTime() + UNDECLARED_GRACE_MS < Date.now()) {
    throw new BadRequestError('Este QR venció. Genera uno nuevo para pagar.', 'PREMIUM_QR_EXPIRED');
  }
  const now = new Date();
  const res = await prisma.premiumPurchase.updateMany({
    where: { id: purchaseId, status: PREMIUM_STATUS.PENDING_PAYMENT },
    // Si declara pasado el vencimiento (dentro del margen), la ventana de revisión del
    // admin vuelve a correr desde ahora, igual que con las reservas.
    data: {
      status: PREMIUM_STATUS.DECLARED,
      paymentDeclaredAt: now,
      ...(purchase.qrExpiresAt && purchase.qrExpiresAt.getTime() < now.getTime()
        ? { qrExpiresAt: new Date(now.getTime() + 15 * 60 * 1000) }
        : {}),
    },
  });
  if (res.count === 0) {
    const fresh = await prisma.premiumPurchase.findUnique({ where: { id: purchaseId } });
    if (fresh?.status === PREMIUM_STATUS.DECLARED || fresh?.status === PREMIUM_STATUS.PAID) return purchaseView(fresh);
    throw new BadRequestError('Este pago ya no está pendiente. Genera un QR nuevo.', 'PREMIUM_NOT_PENDING');
  }
  notifyAdmins(
    '💳 Pago de Premium declarado',
    `Un cuidador dice que pagó Premium de ${purchase.weeks} semana(s) por Bs ${Number(purchase.amount)}. Verifica el depósito y aprueba o rechaza en Pagos.`,
    { type: 'PREMIUM_PAYMENT' }
  ).catch(() => {});
  return purchaseView((await prisma.premiumPurchase.findUnique({ where: { id: purchaseId } }))!);
}

/** POST /api/caregiver/premium/purchases/:id/cancel — solo un QR sin pagar. */
export async function cancelPurchase(userId: string, purchaseId: string) {
  const profile = await ownProfile(userId);
  const res = await prisma.premiumPurchase.updateMany({
    where: { id: purchaseId, caregiverId: profile.id, status: PREMIUM_STATUS.PENDING_PAYMENT },
    data: { status: PREMIUM_STATUS.CANCELLED },
  });
  if (res.count === 0) {
    throw new BadRequestError('Solo se puede cancelar un QR que todavía no pagaste.', 'PREMIUM_NOT_CANCELLABLE');
  }
  return { success: true };
}

// ── Quién paga la comisión (lo elige el cuidador) ────────────────────────────

/** GET /api/caregiver/commission-payer — incluye la comisión de cada servicio (para el ejemplo). */
export async function getMyCommissionPayer(userId: string) {
  const profile = await ownProfile(userId);
  const cfg = await getPricingConfig();
  const next = profile.commissionPaidByChangedAt
    ? new Date(profile.commissionPaidByChangedAt.getTime() + COMMISSION_PAYER_COOLDOWN_MS)
    : null;
  return {
    commissionPaidBy: normalizePayer(profile.commissionPaidBy),
    changedAt: profile.commissionPaidByChangedAt?.toISOString() ?? null,
    nextChangeAt: next && next.getTime() > Date.now() ? next.toISOString() : null,
    commissionPct: Object.fromEntries(PRICED_SERVICES.map((svc) => [svc, resolveCommissionPct(cfg, svc, profile.id)])),
  };
}

/**
 * PUT /api/caregiver/commission-payer — 'CAREGIVER': los dueños ven tu precio sin recargo
 * y la comisión se descuenta de lo que cobras; vale para reservas NUEVAS (las existentes
 * conservan su regla). Como premio apareces antes en el marketplace (sin ninguna marca).
 */
export async function setMyCommissionPayer(userId: string, payerRaw: unknown) {
  if (payerRaw !== 'CLIENT' && payerRaw !== 'CAREGIVER') {
    throw new BadRequestError('Elige quién paga la comisión: CLIENT o CAREGIVER.');
  }
  const payer = payerRaw as CommissionPayer;
  const profile = await ownProfile(userId);
  if (normalizePayer(profile.commissionPaidBy) === payer) return getMyCommissionPayer(userId);
  await prisma.$transaction(async (tx) => {
    await tx.$queryRaw`SELECT id FROM "caregiver_profiles" WHERE id = ${profile.id} FOR UPDATE`;
    const fresh = await tx.caregiverProfile.findUnique({
      where: { id: profile.id },
      select: { premiumUntil: true, commissionPaidByChangedAt: true },
    });
    const last = fresh?.commissionPaidByChangedAt?.getTime() ?? 0;
    if (Date.now() - last < COMMISSION_PAYER_COOLDOWN_MS) {
      const hours = Math.ceil((last + COMMISSION_PAYER_COOLDOWN_MS - Date.now()) / 3_600_000);
      throw new BadRequestError(
        `Ya lo cambiaste hace poco. Podrás volver a cambiarlo en ${hours} hora${hours === 1 ? '' : 's'}.`,
        'COMMISSION_PAYER_COOLDOWN'
      );
    }
    await tx.caregiverProfile.update({
      where: { id: profile.id },
      data: {
        commissionPaidBy: payer,
        commissionPaidByChangedAt: new Date(),
        listingBoost: boostFor({ premiumUntil: fresh?.premiumUntil ?? null, commissionPaidBy: payer }),
      },
    });
  });
  invalidatePricingConfig();
  await invalidateListings(profile.id);
  logger.info('[PREMIUM] quién paga la comisión cambió', { caregiverId: profile.id, payer });
  return getMyCommissionPayer(userId);
}

// ── Admin ────────────────────────────────────────────────────────────────────

async function assertAdminPassword(adminId: string, password: unknown): Promise<void> {
  if (typeof password !== 'string' || password.length === 0) {
    throw new BadRequestError('Escribe tu contraseña de admin.', 'MISSING_PASSWORD');
  }
  const admin = await prisma.user.findUnique({ where: { id: adminId }, select: { passwordHash: true } });
  if (!admin) throw new UnauthorizedError('Admin no encontrado');
  const { comparePassword } = await import('../auth/auth.service.js');
  if (!(await comparePassword(password, admin.passwordHash))) {
    throw new UnauthorizedError('Contraseña de administrador incorrecta', 'INVALID_ADMIN_PASSWORD');
  }
}

function adminPurchaseView(p: any) {
  const user = p.caregiver?.user;
  return {
    ...purchaseView(p),
    qrImageUrl: p.qrImageUrl ?? null,
    note: p.note ?? null,
    autoApprovedAt: p.autoApprovedAt?.toISOString() ?? null,
    reviewedAt: p.reviewedAt?.toISOString() ?? null,
    reviewOutcome: p.reviewOutcome ?? null,
    caregiverId: p.caregiverId,
    caregiverName: p.caregiver?.isCompany && p.caregiver?.companyName
      ? p.caregiver.companyName
      : user ? `${user.firstName ?? ''} ${user.lastName ?? ''}`.trim() : '',
    caregiverEmail: user?.email ?? null,
  };
}

const ADMIN_INCLUDE = {
  caregiver: { select: { isCompany: true, companyName: true, user: { select: { firstName: true, lastName: true, email: true } } } },
} as const;

/** GET /api/admin/premium/purchases?filter=open|all — por defecto lo que espera al admin. */
export async function listPurchasesForAdmin(filter: string | undefined) {
  const where: Prisma.PremiumPurchaseWhereInput =
    filter === 'all'
      ? {}
      : {
          OR: [
            { status: PREMIUM_STATUS.DECLARED },
            { status: PREMIUM_STATUS.PENDING_PAYMENT, qrExpiresAt: { gt: new Date() } },
            { status: PREMIUM_STATUS.PAID, autoApprovedAt: { not: null }, reviewedAt: null },
          ],
        };
  const rows = await prisma.premiumPurchase.findMany({ where, include: ADMIN_INCLUDE, orderBy: { createdAt: 'desc' }, take: 200 });
  return rows.map(adminPurchaseView);
}

/** Lo que espera acción del admin (contador de Pagos). */
export async function countPurchasesNeedingAdmin(): Promise<number> {
  return prisma.premiumPurchase.count({
    where: {
      OR: [
        { status: PREMIUM_STATUS.DECLARED },
        { status: PREMIUM_STATUS.PAID, autoApprovedAt: { not: null }, reviewedAt: null },
      ],
    },
  });
}

/** POST /api/admin/premium/purchases/:id/approve — el dinero llegó. */
export async function approvePurchase(purchaseId: string, adminId: string) {
  const r = await activatePurchase(purchaseId, { decidedBy: adminId });
  if (!r) throw new BadRequestError('Esta compra ya fue procesada o no está pendiente. Actualiza la lista.');
  await prisma.adminAction.create({
    data: { adminId, actionType: 'PREMIUM_APPROVE', targetId: purchaseId, notes: `${r.weeks} sem · Bs ${r.amount}` },
  });
  await afterActivation(r);
  return { success: true, premiumUntil: r.until.toISOString() };
}

/** POST /api/admin/premium/purchases/:id/reject — no llegó el dinero (antes de aprobar). */
export async function rejectPurchase(purchaseId: string, adminId: string, reasonRaw: unknown) {
  const reason = typeof reasonRaw === 'string' ? reasonRaw.trim().slice(0, 300) : '';
  const purchase = await prisma.premiumPurchase.findUnique({ where: { id: purchaseId } });
  if (!purchase) throw new NotFoundError('Compra no encontrada');
  const owner = await prisma.caregiverProfile.findUnique({ where: { id: purchase.caregiverId }, select: { userId: true } });
  const res = await prisma.premiumPurchase.updateMany({
    where: { id: purchaseId, status: { in: OPEN_STATUSES } },
    data: { status: PREMIUM_STATUS.REJECTED, decidedBy: adminId, note: reason || null },
  });
  if (res.count === 0) throw new BadRequestError('Esta compra ya fue procesada o no está pendiente. Actualiza la lista.');
  await prisma.adminAction.create({ data: { adminId, actionType: 'PREMIUM_REJECT', targetId: purchaseId, notes: reason || null } });
  if (owner) await notifyCaregiver(
    owner.userId,
    'Tu pago de Premium no se confirmó',
    `No pudimos verificar tu pago de Bs ${Number(purchase.amount)}.${reason ? ` Motivo: ${reason}.` : ''} Si pagaste, escríbenos a soporte.`,
    'PREMIUM_REJECTED'
  );
  return { success: true };
}

/**
 * Quita una compra PAID (y corre las siguientes hacia adelante). Usada por el admin
 * ("Quitar Premium", con contraseña) y al marcar "no recibido" una aprobada sola.
 */
async function revokePurchaseInternal(purchaseId: string, adminId: string, reason: string, actionType: string) {
  const result = await prisma.$transaction(async (tx) => {
    const purchase = await tx.premiumPurchase.findUnique({ where: { id: purchaseId }, select: { caregiverId: true, status: true } });
    if (!purchase || purchase.status !== PREMIUM_STATUS.PAID) return null;
    await tx.$queryRaw`SELECT id FROM "caregiver_profiles" WHERE id = ${purchase.caregiverId} FOR UPDATE`;
    const res = await tx.premiumPurchase.updateMany({
      where: { id: purchaseId, status: PREMIUM_STATUS.PAID },
      data: { status: PREMIUM_STATUS.REVOKED, decidedBy: adminId, note: reason || null, reviewedAt: new Date() },
    });
    if (res.count === 0) return null;
    const until = await rechainAndRefresh(tx, purchase.caregiverId);
    const profile = await tx.caregiverProfile.findUnique({ where: { id: purchase.caregiverId }, select: { userId: true } });
    return { caregiverId: purchase.caregiverId, userId: profile!.userId, until };
  });
  if (!result) throw new BadRequestError('Esta compra no está activa. Actualiza la lista.');
  await prisma.adminAction.create({ data: { adminId, actionType, targetId: purchaseId, notes: reason || null } });
  await invalidateListings(result.caregiverId);
  return result;
}

/** POST /api/admin/premium/purchases/:id/review — verificar una aprobada sola. */
export async function reviewAutoApproved(purchaseId: string, adminId: string, outcome: unknown) {
  if (outcome !== 'CONFIRMED' && outcome !== 'NOT_RECEIVED') throw new BadRequestError('Resultado inválido.');
  const purchase = await prisma.premiumPurchase.findUnique({ where: { id: purchaseId } });
  if (!purchase) throw new NotFoundError('Compra no encontrada');
  if (!purchase.autoApprovedAt) throw new BadRequestError('Esta compra no se aprobó automáticamente.');
  if (purchase.reviewedAt) throw new BadRequestError('Esta compra ya fue verificada.');
  if (outcome === 'CONFIRMED') {
    const res = await prisma.premiumPurchase.updateMany({
      where: { id: purchaseId, reviewedAt: null },
      data: { reviewedAt: new Date(), reviewOutcome: 'CONFIRMED', decidedBy: adminId },
    });
    if (res.count === 0) throw new BadRequestError('Esta compra ya fue verificada.');
    await prisma.adminAction.create({ data: { adminId, actionType: 'PREMIUM_REVIEW_CONFIRMED', targetId: purchaseId } });
    return { success: true };
  }
  const r = await revokePurchaseInternal(purchaseId, adminId, 'Pago no recibido', 'PREMIUM_REVIEW_NOT_RECEIVED');
  await prisma.premiumPurchase.update({ where: { id: purchaseId }, data: { reviewOutcome: 'NOT_RECEIVED' } });
  await notifyCaregiver(
    r.userId,
    'Tu Premium se pausó',
    'No recibimos el pago de tu Premium, así que lo quitamos. Si pagaste, escríbenos a soporte con el comprobante.',
    'PREMIUM_REVOKED'
  );
  return { success: true };
}

/** POST /api/admin/premium/purchases/:id/revoke — quitar una compra activa (con contraseña). */
export async function revokePurchase(purchaseId: string, adminId: string, input: { reason?: unknown; adminPassword?: unknown }) {
  await assertAdminPassword(adminId, input.adminPassword);
  const reason = typeof input.reason === 'string' ? input.reason.trim().slice(0, 300) : '';
  if (reason.length < 5) throw new BadRequestError('Indica el motivo (mínimo 5 caracteres).');
  const r = await revokePurchaseInternal(purchaseId, adminId, reason, 'PREMIUM_REVOKE');
  await notifyCaregiver(r.userId, 'Cambió tu Premium', `Un administrador quitó parte de tu Premium. Motivo: ${reason}.`, 'PREMIUM_REVOKED');
  return { success: true, premiumUntil: r.until?.toISOString() ?? null };
}

/** GET /api/admin/premium/caregivers/:caregiverId — estado y compras de un perfil. */
export async function getCaregiverPremiumForAdmin(caregiverId: string) {
  const profile = await prisma.caregiverProfile.findUnique({
    where: { id: caregiverId },
    select: { id: true, premiumUntil: true, commissionPaidBy: true, commissionPaidByChangedAt: true, listingBoost: true },
  });
  if (!profile) throw new NotFoundError('Perfil no encontrado');
  const purchases = await prisma.premiumPurchase.findMany({
    where: { caregiverId },
    include: ADMIN_INCLUDE,
    orderBy: { createdAt: 'desc' },
    take: 50,
  });
  return {
    active: !!profile.premiumUntil && profile.premiumUntil.getTime() > Date.now(),
    premiumUntil: profile.premiumUntil?.toISOString() ?? null,
    commissionPaidBy: normalizePayer(profile.commissionPaidBy),
    commissionPaidByChangedAt: profile.commissionPaidByChangedAt?.toISOString() ?? null,
    settings: await getPremiumSettings(),
    purchases: purchases.map(adminPurchaseView),
  };
}

/**
 * POST /api/admin/premium/caregivers/:caregiverId/activate — pago presencial. Cobra el
 * precio de la tabla vigente (el mismo que vería el cuidador) y lo activa al instante.
 */
export async function activateManually(
  caregiverId: string,
  adminId: string,
  input: { weeks?: unknown; paymentKind?: unknown; note?: unknown; adminPassword?: unknown }
) {
  await assertAdminPassword(adminId, input.adminPassword);
  if (!MANUAL_PAYMENT_KINDS.includes(input.paymentKind as ManualPaymentKind)) {
    throw new BadRequestError('Indica cómo pagó: efectivo, transferencia u otro.');
  }
  const profile = await prisma.caregiverProfile.findUnique({ where: { id: caregiverId }, select: { id: true, status: true } });
  if (!profile) throw new NotFoundError('Perfil no encontrado');
  if (profile.status !== 'APPROVED') throw new BadRequestError('Solo un perfil aprobado puede ser Premium.');
  const settings = await getPremiumSettings();
  const amount = quoteOrThrow(settings, input.weeks);
  const note = typeof input.note === 'string' ? input.note.trim().slice(0, 500) : '';
  const purchase = await prisma.$transaction(async (tx) => {
    await tx.$queryRaw`SELECT id FROM "caregiver_profiles" WHERE id = ${caregiverId} FOR UPDATE`;
    // Doble toque / dos admins registrando el mismo pago: el segundo se frena.
    const recent = await tx.premiumPurchase.count({
      where: { caregiverId, method: 'ADMIN', createdAt: { gt: new Date(Date.now() - MANUAL_DUPLICATE_WINDOW_MS) } },
    });
    if (recent > 0) {
      throw new BadRequestError(
        'Ya se registró un pago presencial para este perfil hace un momento. Revisa sus compras antes de cargar otro.',
        'PREMIUM_MANUAL_DUPLICATE'
      );
    }
    return tx.premiumPurchase.create({
      data: {
        caregiverId,
        weeks: Number(input.weeks),
        amount: new Prisma.Decimal(amount),
        method: 'ADMIN',
        manualPaymentKind: input.paymentKind as string,
        note: note || null,
      },
    });
  });
  const r = await activatePurchase(purchase.id, { decidedBy: adminId, fromStatuses: [PREMIUM_STATUS.PENDING_PAYMENT] });
  if (!r) throw new BadRequestError('No se pudo activar. Intenta de nuevo.');
  await prisma.adminAction.create({
    data: {
      adminId,
      actionType: 'PREMIUM_MANUAL',
      targetId: purchase.id,
      notes: `${r.weeks} sem · Bs ${amount} · ${input.paymentKind}${note ? ` · ${note}` : ''}`,
    },
  });
  await afterActivation(r);
  return { success: true, purchaseId: purchase.id, amount, premiumUntil: r.until.toISOString() };
}

/** Ingresos por Premium (PAID) en un rango — para el panel. */
export async function premiumRevenue(from: Date, to: Date): Promise<{ total: number; count: number }> {
  const agg = await prisma.premiumPurchase.aggregate({
    where: { status: PREMIUM_STATUS.PAID, paidAt: { gte: from, lt: to } },
    _sum: { amount: true },
    _count: { _all: true },
  });
  return { total: Number(agg._sum.amount ?? 0), count: agg._count._all };
}

// ── Banco (SIP) ──────────────────────────────────────────────────────────────

/**
 * El banco confirmó un QR cuyo alias es una compra Premium (no una reserva). Devuelve
 * false si el alias no es una compra Premium.
 */
export async function confirmByBank(alias: string): Promise<boolean> {
  const purchase = await prisma.premiumPurchase.findUnique({ where: { id: alias } });
  if (!purchase) return false;
  if (purchase.status === PREMIUM_STATUS.PAID) {
    if (purchase.autoApprovedAt && !purchase.reviewedAt) {
      await prisma.premiumPurchase.updateMany({
        where: { id: alias, reviewedAt: null },
        data: { reviewedAt: new Date(), reviewOutcome: 'CONFIRMED' },
      });
    }
    return true;
  }
  // Cancelada (cambió la duración), vencida o rechazada pero el banco confirma que el
  // dinero llegó: se activa igual — pagó. Una quitada a mano (REVOKED) queda para el admin.
  const LATE_OK: string[] = [PREMIUM_STATUS.CANCELLED, PREMIUM_STATUS.EXPIRED, PREMIUM_STATUS.REJECTED];
  if (!OPEN_STATUSES.includes(purchase.status as any) && !LATE_OK.includes(purchase.status)) {
    logger.error('[PREMIUM] el banco confirmó una compra quitada — revisar a mano', { alias, status: purchase.status });
    notifyAdmins('⚠️ Pago de Premium sobre una compra quitada', `El banco confirmó un pago de Premium (${alias.slice(0, 8)}) que estaba ${purchase.status}. Revísalo a mano.`, { type: 'PREMIUM_PAYMENT' }).catch(() => {});
    return true;
  }
  const r = await activatePurchase(alias, { decidedBy: null, fromStatuses: [...OPEN_STATUSES, ...LATE_OK] });
  if (r) {
    await afterActivation(r);
    if (LATE_OK.includes(purchase.status)) {
      logger.warn('[PREMIUM] el banco confirmó una compra cerrada; se activó', { alias, status: purchase.status });
      notifyAdmins('Premium activado por pago tardío', `El banco confirmó un pago de Premium (${alias.slice(0, 8)}) que estaba ${purchase.status}; se activó.`, { type: 'PREMIUM_PAYMENT' }).catch(() => {});
    }
  }
  return true;
}

// ── Job (cada 5 min, ver jobs/premium.job.ts) ────────────────────────────────

export async function runPremiumMaintenance(now = new Date()): Promise<{
  expired: number; autoApproved: number; ended: number; reminded: number;
}> {
  // 1) QR sin "ya pagué" vencidos (con margen) → EXPIRED.
  const expired = await prisma.premiumPurchase.updateMany({
    where: { status: PREMIUM_STATUS.PENDING_PAYMENT, method: 'QR', qrExpiresAt: { lt: new Date(now.getTime() - UNDECLARED_GRACE_MS) } },
    data: { status: PREMIUM_STATUS.EXPIRED },
  });

  // 2) Declarados sin revisión al vencer el QR → se aprueban solos (como las reservas).
  const due = await prisma.premiumPurchase.findMany({
    where: { status: PREMIUM_STATUS.DECLARED, qrExpiresAt: { lt: now } },
    select: { id: true },
  });
  let autoApproved = 0;
  for (const d of due) {
    try {
      const r = await activatePurchase(d.id, { decidedBy: null, autoApproved: true, fromStatuses: [PREMIUM_STATUS.DECLARED] });
      if (r) {
        autoApproved++;
        await afterActivation(r);
      }
    } catch (err) {
      logger.error('[PREMIUM] no se pudo aprobar automáticamente', { purchaseId: d.id, err });
    }
  }
  if (autoApproved > 0) {
    notifyAdmins(
      '✅ Premium aprobado automáticamente',
      `${autoApproved} pago(s) de Premium se aprobaron solos porque nadie los revisó a tiempo. Verifica si el dinero llegó en Pagos.`,
      { type: 'PREMIUM_PAYMENT' }
    ).catch(() => {});
  }

  // 3) Premium vencido → baja en el marketplace y aviso.
  const ending = await prisma.caregiverProfile.findMany({
    where: { listingBoost: 2, OR: [{ premiumUntil: null }, { premiumUntil: { lte: now } }] },
    select: { id: true, userId: true },
  });
  let ended = 0;
  for (const p of ending) {
    // Condicionado también a quién paga la comisión, por si lo cambia justo ahora.
    const stillEnded = { id: p.id, listingBoost: 2, OR: [{ premiumUntil: null }, { premiumUntil: { lte: now } }] };
    const a = await prisma.caregiverProfile.updateMany({
      where: { ...stillEnded, commissionPaidBy: 'CAREGIVER' },
      data: { listingBoost: 1 },
    });
    const b = await prisma.caregiverProfile.updateMany({
      where: { ...stillEnded, NOT: { commissionPaidBy: 'CAREGIVER' } },
      data: { listingBoost: 0 },
    });
    if (a.count + b.count > 0) {
      ended++;
      await invalidateListings(p.id);
      await notifyCaregiver(p.userId, 'Tu Premium terminó', 'Ya no apareces como Destacado. Puedes renovarlo cuando quieras desde Garden Premium.', 'PREMIUM_EXPIRED');
    }
  }

  // 4) Aviso 3 días antes de vencer (una vez por período).
  const soon = await prisma.caregiverProfile.findMany({
    where: {
      premiumUntil: { gt: now, lte: new Date(now.getTime() + REMINDER_BEFORE_MS) },
      premiumReminderSentAt: null,
    },
    select: { id: true, userId: true, premiumUntil: true },
  });
  let reminded = 0;
  for (const p of soon) {
    const res = await prisma.caregiverProfile.updateMany({
      where: { id: p.id, premiumReminderSentAt: null },
      data: { premiumReminderSentAt: now },
    });
    if (res.count > 0) {
      reminded++;
      await notifyCaregiver(p.userId, 'Tu Premium vence pronto', `Tu Premium termina el ${fmtDate(p.premiumUntil!)}. Renuévalo para seguir apareciendo primero.`, 'PREMIUM_EXPIRING');
    }
  }
  return { expired: expired.count, autoApproved, ended, reminded };
}
