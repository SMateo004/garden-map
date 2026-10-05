/**
 * Aceptación periódica de los Términos, la Política de Privacidad y el Contrato de Cuidador.
 *
 * Regla de negocio (ver Términos, sección 32): el Cuidador debe volver a aceptar cada 2 meses
 * (60 días) desde su última aceptación — haya prestado servicios o no — y también cuando Garden
 * publique una versión nueva de los textos.
 *
 * Dónde se guarda:
 *  - `CaregiverProfile.termsAcceptedAt`: fecha de la ÚLTIMA aceptación (fuente del vencimiento).
 *  - `AuditLog` (action CAREGIVER_TERMS_ACCEPTED): historial completo con versión, fecha, IP y
 *    dispositivo. Solo lo lee el admin (detalle del cuidador); el Cuidador nunca lo ve.
 *    No requiere cambios de esquema.
 *
 * Qué pasa si vence: el perfil sale del marketplace y no puede recibir reservas nuevas. Lo ya
 * reservado se atiende hasta el final y lo ya ganado no se pierde.
 */
import prisma from '../../config/database.js';
import { getCache, delByPrefix } from '../../shared/cache.js';
import { NotFoundError } from '../../shared/errors.js';
import type { Prisma } from '@prisma/client';

/** Versión del texto vigente. Al cambiar los textos legales: subir esto y CAREGIVER_TERMS_EFFECTIVE_AT. */
export const CAREGIVER_TERMS_VERSION = '2026-10-05';
/** Desde cuándo rige esa versión: quien aceptó antes de esta fecha debe aceptar de nuevo. */
export const CAREGIVER_TERMS_EFFECTIVE_AT = new Date('2026-10-05T04:00:00.000Z');
/** Vencimiento periódico: cada 2 meses. */
export const TERMS_RENEWAL_DAYS = 60;
/** Aviso previo al vencimiento. */
export const TERMS_REMINDER_DAYS = 7;
/** Tras publicar una versión nueva, plazo antes de ocultar a quien aún no la aceptó. */
export const TERMS_VERSION_GRACE_DAYS = 7;

export const TERMS_AUDIT_ACTION = 'CAREGIVER_TERMS_ACCEPTED';
const DAY_MS = 24 * 60 * 60 * 1000;

export type TermsSource = 'REGISTRATION' | 'PERIODIC';

/**
 * Cuentas de prueba para la revisión de las tiendas (Apple / Google): reviewer.admin, reviewer.cliente y
 * reviewer.cuidador, SIEMPRE con el dominio propio de Garden. Quedan exentas de la renovación periódica para
 * que el cuidador de prueba no desaparezca del marketplace en plena revisión. No se puede falsear: registrar
 * un correo @gardenbo.com exige verificarlo por código en ese buzón.
 */
const EXEMPT_EMAIL_PREFIX = 'reviewer.';
const EXEMPT_EMAIL_DOMAIN = '@gardenbo.com';

export function isTermsExemptEmail(email: string | null | undefined): boolean {
  const e = (email ?? '').trim().toLowerCase();
  return e.startsWith(EXEMPT_EMAIL_PREFIX) && e.endsWith(EXEMPT_EMAIL_DOMAIN) && e.length > EXEMPT_EMAIL_PREFIX.length + EXEMPT_EMAIL_DOMAIN.length;
}

export interface TermsStatus {
  /** El Cuidador debe aceptar ahora (la app le muestra la pantalla de aceptación). */
  required: boolean;
  /** Ya se aplican las restricciones (fuera del marketplace, sin reservas nuevas). */
  blocked: boolean;
  /** Cuenta de prueba de las tiendas (reviewer.*): no se le exige renovar. */
  exempt: boolean;
  /** Motivo de `required`: nunca aceptó / venció a los 60 días / hay una versión nueva. */
  reason: 'NEVER' | 'EXPIRED' | 'NEW_VERSION' | null;
  lastAcceptedAt: Date | null;
  dueAt: Date | null;
  daysLeft: number | null;
  /** Falta poco para el vencimiento (<= TERMS_REMINDER_DAYS) y todavía no venció. */
  reminderDue: boolean;
  version: string;
}

/** Fecha mínima de `termsAcceptedAt` para que una aceptación siga cumpliendo el vencimiento. */
export function renewalCutoff(now: Date = new Date()): Date {
  return new Date(now.getTime() - TERMS_RENEWAL_DAYS * DAY_MS);
}

/**
 * Fecha mínima de `termsAcceptedAt` para NO ser ocultado del marketplace ni bloqueado: el corte
 * de 60 días y, pasada la gracia de una versión nueva, también la fecha de vigencia de esa versión.
 * Es el valor que se usa en los `where` de Prisma (listado público, detalle y reservas).
 */
export function termsEnforcementFrom(now: Date = new Date()): Date {
  const cutoff = renewalCutoff(now);
  const graceEnds = CAREGIVER_TERMS_EFFECTIVE_AT.getTime() + TERMS_VERSION_GRACE_DAYS * DAY_MS;
  if (now.getTime() >= graceEnds && CAREGIVER_TERMS_EFFECTIVE_AT > cutoff) return CAREGIVER_TERMS_EFFECTIVE_AT;
  return cutoff;
}

/**
 * Fragmento `where` de Prisma con la condición "aceptación vigente", para el listado público, el detalle y las
 * reservas: pasa quien aceptó a tiempo O es una cuenta de prueba exenta. Usar dentro de `AND: [...]`.
 */
export function termsGateWhere(now: Date = new Date()): Prisma.CaregiverProfileWhereInput {
  return {
    OR: [
      { termsAcceptedAt: { gte: termsEnforcementFrom(now) } },
      { user: { email: { startsWith: EXEMPT_EMAIL_PREFIX, endsWith: EXEMPT_EMAIL_DOMAIN, mode: 'insensitive' } } },
    ],
  };
}

export function computeTermsStatus(
  lastAcceptedAt: Date | null | undefined,
  now: Date = new Date(),
  opts: { exempt?: boolean } = {},
): TermsStatus {
  const last = lastAcceptedAt ?? null;
  const base = { lastAcceptedAt: last, version: CAREGIVER_TERMS_VERSION, exempt: opts.exempt === true };

  if (opts.exempt) {
    const dueAt = last ? new Date(last.getTime() + TERMS_RENEWAL_DAYS * DAY_MS) : null;
    return { ...base, required: false, blocked: false, reason: null, dueAt, daysLeft: null, reminderDue: false };
  }

  if (!last) {
    return { ...base, required: true, blocked: true, reason: 'NEVER', dueAt: null, daysLeft: null, reminderDue: false };
  }

  const dueAt = new Date(last.getTime() + TERMS_RENEWAL_DAYS * DAY_MS);
  if (now.getTime() >= dueAt.getTime()) {
    return { ...base, required: true, blocked: true, reason: 'EXPIRED', dueAt, daysLeft: 0, reminderDue: false };
  }

  const daysLeft = Math.ceil((dueAt.getTime() - now.getTime()) / DAY_MS);
  if (last < CAREGIVER_TERMS_EFFECTIVE_AT) {
    return {
      ...base, required: true, blocked: last < termsEnforcementFrom(now), reason: 'NEW_VERSION', dueAt, daysLeft, reminderDue: false,
    };
  }
  return { ...base, required: false, blocked: false, reason: null, dueAt, daysLeft, reminderDue: daysLeft <= TERMS_REMINDER_DAYS };
}

export async function getTermsStatusForUser(userId: string): Promise<TermsStatus> {
  const profile = await prisma.caregiverProfile.findUnique({
    where: { userId },
    select: { termsAcceptedAt: true, user: { select: { email: true } } },
  });
  if (!profile) throw new NotFoundError('Perfil de cuidador no encontrado');
  return computeTermsStatus(profile.termsAcceptedAt, new Date(), { exempt: isTermsExemptEmail(profile.user?.email) });
}

/**
 * Registra una aceptación: guarda la evidencia (AuditLog, con espera — no fire-and-forget, porque es
 * prueba legal: si no se puede guardar, la aceptación no vale) y actualiza la fecha vigente.
 */
export async function recordCaregiverTermsAcceptance(
  userId: string,
  meta: { source: TermsSource; ip?: string | null; userAgent?: string | null },
): Promise<TermsStatus> {
  const profile = await prisma.caregiverProfile.findUnique({ where: { userId }, select: { id: true, user: { select: { email: true } } } });
  if (!profile) throw new NotFoundError('Perfil de cuidador no encontrado');

  const now = new Date();
  await prisma.$transaction([
    prisma.auditLog.create({
      data: {
        userId,
        action: TERMS_AUDIT_ACTION,
        entity: 'CaregiverProfile',
        entityId: profile.id,
        details: JSON.stringify({
          version: CAREGIVER_TERMS_VERSION,
          source: meta.source,
          acceptedAt: now.toISOString(),
          documents: ['TERMS', 'PRIVACY', 'CAREGIVER_CONTRACT'],
          userAgent: meta.userAgent ? meta.userAgent.slice(0, 300) : null,
        }),
        ip: meta.ip ? meta.ip.slice(0, 45) : null,
      },
    }),
    prisma.caregiverProfile.update({
      where: { id: profile.id },
      data: {
        termsAcceptedAt: now,
        termsAccepted: true,
        privacyAccepted: true,
        contractAcceptedAt: now,
      } as any,
    }),
  ]);

  // El listado público y el detalle filtran por esta fecha: que el cambio se vea ya.
  await delByPrefix('caregivers:list:');
  await getCache().del(`caregivers:detail:${profile.id}`);

  return computeTermsStatus(now, now, { exempt: isTermsExemptEmail(profile.user?.email) });
}

export interface TermsAcceptanceEntry {
  version: string | null;
  source: string | null;
  acceptedAt: string;
  ip: string | null;
  userAgent: string | null;
}

/** Historial de aceptaciones — SOLO para el panel admin. */
export async function listTermsAcceptances(profileId: string, limit = 24): Promise<TermsAcceptanceEntry[]> {
  const rows = await prisma.auditLog.findMany({
    where: { action: TERMS_AUDIT_ACTION, entity: 'CaregiverProfile', entityId: profileId },
    orderBy: { createdAt: 'desc' },
    take: limit,
  });
  return rows.map((r) => {
    let d: Record<string, unknown> = {};
    try { d = r.details ? (JSON.parse(r.details) as Record<string, unknown>) : {}; } catch { /* details corrupto: se muestra igual */ }
    return {
      version: typeof d.version === 'string' ? d.version : null,
      source: typeof d.source === 'string' ? d.source : null,
      acceptedAt: typeof d.acceptedAt === 'string' ? d.acceptedAt : r.createdAt.toISOString(),
      ip: r.ip,
      userAgent: typeof d.userAgent === 'string' ? d.userAgent : null,
    };
  });
}
