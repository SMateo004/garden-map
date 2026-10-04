/**
 * Invitaciones de registro profesional: un código por persona, un solo uso, con vencimiento.
 * Solo se guarda el hash SHA-256; el código en claro se devuelve una única vez al crearlo.
 */
import { createHash, randomInt } from 'crypto';
import type { Prisma, ProfessionalInvite } from '@prisma/client';
import prisma from '../../config/database.js';
import { BadRequestError, NotFoundError } from '../../shared/errors.js';

// Sin 0/O/1/I/L para que se pueda dictar por teléfono sin confusiones.
const ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
const DEFAULT_EXPIRY_DAYS = 7;
const MAX_EXPIRY_DAYS = 60;

export function normalizeInviteCode(code: string): string {
  return code.trim().toUpperCase().replace(/\s+/g, '');
}

export function hashInviteCode(code: string): string {
  return createHash('sha256').update(normalizeInviteCode(code)).digest('hex');
}

/**
 * Tipo de invitación. Se distingue por el prefijo del código (GP- profesional, GE- empresa) y no
 * por una columna: así un código de profesional jamás sirve para registrar una empresa (ni al
 * revés) sin tocar el esquema de producción. La etiqueta de las de empresa lleva EMPRESA_TAG para
 * poder listarlas por tipo.
 */
export type InviteKind = 'PROFESSIONAL' | 'COMPANY';
const PREFIX: Record<InviteKind, string> = { PROFESSIONAL: 'GP-', COMPANY: 'GE-' };
const EMPRESA_TAG = '[Empresa] ';

export function inviteKindOfLabel(label: string): InviteKind {
  return label.startsWith(EMPRESA_TAG) ? 'COMPANY' : 'PROFESSIONAL';
}

function generateCode(kind: InviteKind): string {
  const chunk = () => Array.from({ length: 4 }, () => ALPHABET[randomInt(ALPHABET.length)]).join('');
  return `${PREFIX[kind]}${chunk()}-${chunk()}`;
}

export type InviteStatus = 'ACTIVE' | 'USED' | 'EXPIRED' | 'REVOKED';

export function inviteStatus(i: Pick<ProfessionalInvite, 'usedAt' | 'revokedAt' | 'expiresAt'>, now = new Date()): InviteStatus {
  if (i.usedAt) return 'USED';
  if (i.revokedAt) return 'REVOKED';
  if (i.expiresAt <= now) return 'EXPIRED';
  return 'ACTIVE';
}

export async function createInvite(adminId: string, label: string, expiresInDays?: number, kind: InviteKind = 'PROFESSIONAL') {
  const cleanLabel = label.trim();
  if (!cleanLabel) throw new BadRequestError('Indica para quién es la invitación.', 'MISSING_LABEL');
  const days = Math.min(Math.max(Math.floor(expiresInDays ?? DEFAULT_EXPIRY_DAYS), 1), MAX_EXPIRY_DAYS);
  const expiresAt = new Date(Date.now() + days * 24 * 60 * 60 * 1000);

  const code = generateCode(kind);
  const storedLabel = (kind === 'COMPANY' ? EMPRESA_TAG : '') + cleanLabel;
  const invite = await prisma.professionalInvite.create({
    data: { codeHash: hashInviteCode(code), label: storedLabel.slice(0, 120), createdBy: adminId, expiresAt },
  });
  await prisma.adminAction.create({
    data: { adminId, actionType: kind === 'COMPANY' ? 'CREATE_COMPANY_INVITE' : 'CREATE_PROFESSIONAL_INVITE', targetId: invite.id, notes: cleanLabel },
  });
  // `code` solo sale de acá: no se puede recuperar después (solo está el hash).
  return { id: invite.id, code, label: cleanLabel, kind, expiresAt: invite.expiresAt };
}

export async function listInvites() {
  const rows = await prisma.professionalInvite.findMany({ orderBy: { createdAt: 'desc' }, take: 100 });
  return rows.map((r) => ({
    id: r.id,
    kind: inviteKindOfLabel(r.label),
    label: r.label.startsWith(EMPRESA_TAG) ? r.label.slice(EMPRESA_TAG.length) : r.label,
    status: inviteStatus(r),
    expiresAt: r.expiresAt,
    usedAt: r.usedAt,
    createdAt: r.createdAt,
  }));
}

export async function revokeInvite(adminId: string, id: string) {
  const invite = await prisma.professionalInvite.findUnique({ where: { id } });
  if (!invite) throw new NotFoundError('Invitación no encontrada');
  if (invite.usedAt) throw new BadRequestError('Esa invitación ya fue usada.', 'INVITE_ALREADY_USED');
  await prisma.professionalInvite.update({ where: { id }, data: { revokedAt: new Date() } });
  await prisma.adminAction.create({
    data: { adminId, actionType: 'REVOKE_PROFESSIONAL_INVITE', targetId: id, notes: invite.label },
  });
}

/**
 * Devuelve la invitación si el código es válido (existe, sin usar, sin revocar, vigente) Y es del
 * tipo pedido: el prefijo del código tiene que coincidir con `kind`.
 */
export async function findValidInvite(code: string, kind: InviteKind = 'PROFESSIONAL'): Promise<ProfessionalInvite | null> {
  if (!code || !code.trim()) return null;
  if (!normalizeInviteCode(code).startsWith(PREFIX[kind])) return null;
  const invite = await prisma.professionalInvite.findUnique({ where: { codeHash: hashInviteCode(code) } });
  if (!invite || inviteStatus(invite) !== 'ACTIVE') return null;
  return invite;
}

/**
 * Marca la invitación como usada DENTRO de la transacción del registro. El updateMany
 * condicionado es atómico: si dos personas envían el mismo código a la vez, solo una
 * consigue count=1 y la otra aborta (la transacción hace rollback del usuario creado).
 */
export async function consumeInvite(tx: Prisma.TransactionClient, inviteId: string, userId: string): Promise<void> {
  const res = await tx.professionalInvite.updateMany({
    where: { id: inviteId, usedAt: null, revokedAt: null, expiresAt: { gt: new Date() } },
    data: { usedAt: new Date(), usedByUserId: userId },
  });
  if (res.count !== 1) {
    throw new BadRequestError('Código de registro inválido.', 'INVALID_INVITE_CODE');
  }
}
