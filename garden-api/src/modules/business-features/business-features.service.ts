/**
 * Funciones de negocio habilitables por el admin, por negocio y a pedido.
 *
 * Regla (definida con el founder, 2026-10-09): la recepción para clientes que llegan sin la
 * app y las funciones de equipo NO vienen activas — un negocio las solicita y SOLO el admin
 * las enciende o apaga (Admin > Cuidadores > detalle > Funciones del negocio). Cada función
 * aplica a ciertos tipos de cuenta (individual, profesional, empresa); para los demás no existe.
 *
 * Se guardan en CaregiverProfile.businessFeatures ({ CLAVE: true }). Ausente = apagada.
 * Una función que depende de otra (ej. permisos del equipo dependen del equipo) solo queda
 * activa si su dependencia también lo está.
 */
import prisma from '../../config/database.js';
import { ForbiddenError, NotFoundError } from '../../shared/errors.js';

export type BusinessFeature = 'RECEPTION' | 'STAFF_TEAM' | 'STAFF_BOOKING_DECISIONS' | 'STAFF_CLIENT_CHAT';
export type CaregiverKind = 'INDIVIDUAL' | 'PROFESSIONAL' | 'COMPANY';

export interface BusinessFeatureDef {
  key: BusinessFeature;
  label: string;
  description: string;
  appliesTo: CaregiverKind[];
  requires?: BusinessFeature;
}

export const BUSINESS_FEATURES: readonly BusinessFeatureDef[] = [
  {
    key: 'RECEPTION',
    label: 'Recepción',
    description: 'Clientes que llegan al local sin la app: fichas, entradas y salidas, reservas de mostrador, ocupación y reportes de caja.',
    appliesTo: ['COMPANY'],
  },
  {
    key: 'STAFF_TEAM',
    label: 'Equipo',
    description: 'Invitar empleados con su propia cuenta para atender reservas, y asignarles reservas.',
    appliesTo: ['COMPANY'],
  },
  {
    key: 'STAFF_BOOKING_DECISIONS',
    label: 'Equipo: aceptar y rechazar reservas',
    description: 'Los empleados que el dueño autorice pueden aceptar o rechazar reservas nuevas.',
    appliesTo: ['COMPANY'],
    requires: 'STAFF_TEAM',
  },
  {
    key: 'STAFF_CLIENT_CHAT',
    label: 'Equipo: chat con clientes',
    description: 'Los empleados que el dueño autorice pueden chatear con los clientes de sus reservas.',
    appliesTo: ['COMPANY'],
    requires: 'STAFF_TEAM',
  },
];

export const BUSINESS_FEATURE_KEYS = BUSINESS_FEATURES.map((f) => f.key);

export type FeatureMap = Record<BusinessFeature, boolean>;

interface ProfileLike {
  isCompany?: boolean | null;
  isProfessional?: boolean | null;
  businessFeatures?: unknown;
}

export function kindOf(p: ProfileLike): CaregiverKind {
  if (p.isCompany) return 'COMPANY';
  if (p.isProfessional) return 'PROFESSIONAL';
  return 'INDIVIDUAL';
}

function stored(p: ProfileLike): Partial<Record<BusinessFeature, boolean>> {
  const raw = p.businessFeatures;
  return raw && typeof raw === 'object' && !Array.isArray(raw) ? (raw as Partial<Record<BusinessFeature, boolean>>) : {};
}

/** Estado efectivo de cada función: aplica al tipo de cuenta, está encendida y su dependencia también. */
export function resolveFeatures(p: ProfileLike): FeatureMap {
  const kind = kindOf(p);
  const raw = stored(p);
  const out = {} as FeatureMap;
  for (const f of BUSINESS_FEATURES) out[f.key] = f.appliesTo.includes(kind) && raw[f.key] === true;
  for (const f of BUSINESS_FEATURES) if (f.requires && !out[f.requires]) out[f.key] = false;
  return out;
}

export async function getFeaturesForProfile(caregiverProfileId: string): Promise<FeatureMap> {
  const p = await prisma.caregiverProfile.findUnique({
    where: { id: caregiverProfileId },
    select: { isCompany: true, isProfessional: true, businessFeatures: true },
  });
  if (!p) throw new NotFoundError('Cuidador no encontrado');
  return resolveFeatures(p);
}

export const FEATURE_DISABLED_MESSAGE: Record<BusinessFeature, string> = {
  RECEPTION: 'La recepción no está habilitada para tu negocio. Puedes solicitarla a soporte de GARDEN.',
  STAFF_TEAM: 'El equipo no está habilitado para tu negocio. Puedes solicitarlo a soporte de GARDEN.',
  STAFF_BOOKING_DECISIONS: 'Que el equipo acepte o rechace reservas no está habilitado para este negocio.',
  STAFF_CLIENT_CHAT: 'El chat del equipo con clientes no está habilitado para este negocio.',
};

export async function assertFeature(caregiverProfileId: string, feature: BusinessFeature): Promise<void> {
  const features = await getFeaturesForProfile(caregiverProfileId);
  if (!features[feature]) throw new ForbiddenError(FEATURE_DISABLED_MESSAGE[feature], 'FEATURE_DISABLED');
}

/** Para el admin: catálogo con el estado efectivo y el guardado, solo de las funciones que aplican. */
export async function getFeaturesAdminView(caregiverProfileId: string) {
  const p = await prisma.caregiverProfile.findUnique({
    where: { id: caregiverProfileId },
    select: { id: true, isCompany: true, isProfessional: true, businessFeatures: true, companyName: true },
  });
  if (!p) throw new NotFoundError('Cuidador no encontrado');
  const kind = kindOf(p);
  const raw = stored(p);
  const effective = resolveFeatures(p);
  return {
    caregiverProfileId: p.id,
    kind,
    features: BUSINESS_FEATURES.filter((f) => f.appliesTo.includes(kind)).map((f) => ({
      key: f.key,
      label: f.label,
      description: f.description,
      requires: f.requires ?? null,
      enabled: raw[f.key] === true,
      effective: effective[f.key],
    })),
  };
}

/** Solo el admin: enciende/apaga funciones de un negocio. Ignora claves que no aplican a su tipo. */
export async function setFeatures(
  caregiverProfileId: string,
  changes: Partial<Record<BusinessFeature, boolean>>
): Promise<{ before: Partial<Record<BusinessFeature, boolean>>; after: Partial<Record<BusinessFeature, boolean>> }> {
  const p = await prisma.caregiverProfile.findUnique({
    where: { id: caregiverProfileId },
    select: { isCompany: true, isProfessional: true, businessFeatures: true },
  });
  if (!p) throw new NotFoundError('Cuidador no encontrado');
  const kind = kindOf(p);
  const before = stored(p);
  const after: Partial<Record<BusinessFeature, boolean>> = { ...before };
  for (const f of BUSINESS_FEATURES) {
    if (!(f.key in changes)) continue;
    if (!f.appliesTo.includes(kind)) {
      throw new ForbiddenError(`"${f.label}" no aplica a este tipo de cuenta`, 'FEATURE_NOT_APPLICABLE');
    }
    if (changes[f.key]) after[f.key] = true;
    else delete after[f.key];
  }
  await prisma.caregiverProfile.update({ where: { id: caregiverProfileId }, data: { businessFeatures: after } });
  return { before, after };
}
