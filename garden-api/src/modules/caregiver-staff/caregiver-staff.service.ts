/**
 * Staff multiusuario para cuentas EMPRESA (isCompany=true) — hoteles y
 * guarderías. Un empleado tiene su PROPIA cuenta (User.role=CAREGIVER) pero
 * NUNCA un CaregiverProfile propio: su identidad de negocio se resuelve
 * siempre a través de CaregiverStaffMember. Esto deja intactas todas las
 * rutas /api/caregiver/* existentes (si un token de staff les pega, fallan
 * solas por no tener perfil propio) y limita lo que el staff puede hacer a
 * lo que expone /api/caregiver-staff/* — ver caregiver-staff.routes.ts.
 */
import { randomBytes } from 'crypto';
import { UserRole } from '@prisma/client';
import prisma from '../../config/database.js';
import { BadRequestError, ConflictError, ForbiddenError, NotFoundError } from '../../shared/errors.js';
import { hashPassword, signAccessToken, createRefreshToken } from '../auth/auth.service.js';
import type { JwtPayload } from '../../middleware/auth.middleware.js';
import type { z } from 'zod';
import type { registerStaffBodySchema } from './caregiver-staff.validation.js';

type RegisterStaffBody = z.infer<typeof registerStaffBodySchema>;

export interface StaffContext {
  caregiverProfileId: string;
  ownerUserId: string;
  companyName: string | null;
  staffMemberId: string;
}

function generateCode(): string {
  // 8 chars alfanuméricos en mayúscula — corto para compartir de palabra/WhatsApp,
  // suficientemente amplio (36^8) para no colisionar en la práctica.
  return randomBytes(6).toString('hex').toUpperCase().slice(0, 8);
}

async function assertIsCompanyOwner(ownerUserId: string) {
  const profile = await prisma.caregiverProfile.findFirst({ where: { userId: ownerUserId } });
  if (!profile) throw new NotFoundError('No tenés un perfil de cuidador');
  if (!profile.isCompany) {
    throw new ForbiddenError('Solo las cuentas empresa pueden tener empleados');
  }
  return profile;
}

export async function generateInviteCode(
  ownerUserId: string,
  label?: string,
  expiresInDays = 7
): Promise<{ id: string; code: string; expiresAt: Date; label: string | null }> {
  const profile = await assertIsCompanyOwner(ownerUserId);
  const expiresAt = new Date(Date.now() + expiresInDays * 24 * 60 * 60 * 1000);

  // Colisión de código es astronómicamente improbable pero barata de manejar —
  // reintenta una vez si el @unique la rechaza.
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      const invite = await prisma.caregiverStaffInvite.create({
        data: {
          caregiverProfileId: profile.id,
          code: generateCode(),
          createdByUserId: ownerUserId,
          expiresAt,
          label: label ?? null,
        },
      });
      return { id: invite.id, code: invite.code, expiresAt: invite.expiresAt, label: invite.label };
    } catch (err: any) {
      if (err?.code === 'P2002' && attempt < 2) continue;
      throw err;
    }
  }
  throw new BadRequestError('No se pudo generar el código, intentá de nuevo');
}

export async function listInvites(ownerUserId: string) {
  const profile = await assertIsCompanyOwner(ownerUserId);
  return prisma.caregiverStaffInvite.findMany({
    where: { caregiverProfileId: profile.id },
    orderBy: { createdAt: 'desc' },
  });
}

export async function revokeInvite(ownerUserId: string, inviteId: string): Promise<void> {
  const profile = await assertIsCompanyOwner(ownerUserId);
  const invite = await prisma.caregiverStaffInvite.findUnique({ where: { id: inviteId } });
  if (!invite || invite.caregiverProfileId !== profile.id) {
    throw new NotFoundError('Invitación no encontrada');
  }
  if (invite.status !== 'PENDING') {
    throw new BadRequestError('Esa invitación ya no está pendiente');
  }
  await prisma.caregiverStaffInvite.update({ where: { id: inviteId }, data: { status: 'REVOKED' } });
}

export async function previewInvite(code: string): Promise<{ companyName: string; valid: boolean }> {
  const invite = await prisma.caregiverStaffInvite.findUnique({
    where: { code: code.trim().toUpperCase() },
    include: { caregiverProfile: { select: { companyName: true } } },
  });
  const valid = !!invite && invite.status === 'PENDING' && invite.expiresAt > new Date();
  return { companyName: invite?.caregiverProfile.companyName ?? '', valid };
}

export async function listStaffMembers(ownerUserId: string) {
  const profile = await assertIsCompanyOwner(ownerUserId);
  const members = await prisma.caregiverStaffMember.findMany({
    where: { caregiverProfileId: profile.id },
    orderBy: { createdAt: 'desc' },
    include: { user: { select: { firstName: true, lastName: true, email: true, phone: true } } },
  });
  return members.map((m) => ({
    id: m.id,
    status: m.status,
    firstName: m.user.firstName,
    lastName: m.user.lastName,
    email: m.user.email,
    phone: m.user.phone,
    invitedAt: m.invitedAt,
    joinedAt: m.joinedAt,
    removedAt: m.removedAt,
  }));
}

async function assertOwnsStaffMember(ownerUserId: string, staffMemberId: string) {
  const profile = await assertIsCompanyOwner(ownerUserId);
  const member = await prisma.caregiverStaffMember.findUnique({ where: { id: staffMemberId } });
  if (!member || member.caregiverProfileId !== profile.id) {
    throw new NotFoundError('Empleado no encontrado');
  }
  return member;
}

export async function removeStaffMember(ownerUserId: string, staffMemberId: string, reason?: string): Promise<void> {
  await assertOwnsStaffMember(ownerUserId, staffMemberId);
  await prisma.caregiverStaffMember.update({
    where: { id: staffMemberId },
    data: { status: 'REMOVED', removedAt: new Date(), removedByUserId: ownerUserId, removalReason: reason ?? null },
  });
}

export async function suspendStaffMember(ownerUserId: string, staffMemberId: string): Promise<void> {
  const member = await assertOwnsStaffMember(ownerUserId, staffMemberId);
  if (member.status !== 'ACTIVE') throw new BadRequestError('Ese empleado no está activo');
  await prisma.caregiverStaffMember.update({ where: { id: staffMemberId }, data: { status: 'SUSPENDED' } });
}

export async function reactivateStaffMember(ownerUserId: string, staffMemberId: string): Promise<void> {
  const member = await assertOwnsStaffMember(ownerUserId, staffMemberId);
  if (member.status !== 'SUSPENDED') throw new BadRequestError('Ese empleado no está suspendido');
  await prisma.caregiverStaffMember.update({ where: { id: staffMemberId }, data: { status: 'ACTIVE' } });
}

export interface RegisterStaffResult {
  accessToken: string;
  refreshToken: string;
  expiresIn: string;
  user: { id: string; email: string; role: string; firstName: string; lastName: string };
  isCaregiverStaff: true;
  staffCompanyName: string | null;
}

export async function registerStaffMember(body: RegisterStaffBody): Promise<RegisterStaffResult> {
  const code = body.code.trim().toUpperCase();
  const invite = await prisma.caregiverStaffInvite.findUnique({
    where: { code },
    include: { caregiverProfile: { select: { id: true, companyName: true } } },
  });
  if (!invite || invite.status !== 'PENDING') {
    throw new BadRequestError('Código de invitación inválido o ya usado', 'INVALID_STAFF_CODE');
  }
  if (invite.expiresAt <= new Date()) {
    throw new BadRequestError('Ese código de invitación venció', 'STAFF_CODE_EXPIRED');
  }

  const email = body.email.toLowerCase().trim();
  const [existingEmail, existingPhone] = await Promise.all([
    prisma.user.findUnique({ where: { email } }),
    prisma.user.findUnique({ where: { phone: body.phone } }),
  ]);
  if (existingEmail) throw new ConflictError('Ya existe una cuenta con este email', 'EMAIL_EXISTS', 'email');
  if (existingPhone) throw new ConflictError('Ya existe una cuenta con este teléfono', 'PHONE_EXISTS', 'phone');

  const passwordHash = await hashPassword(body.password);
  const now = new Date();

  const { user } = await prisma.$transaction(async (tx) => {
    const user = await tx.user.create({
      data: {
        email,
        passwordHash,
        role: UserRole.CAREGIVER,
        firstName: body.firstName.trim(),
        lastName: body.lastName.trim(),
        phone: body.phone.trim(),
        country: 'Bolivia',
        city: 'Santa Cruz de la Sierra',
        isOver18: true,
        emailVerified: false,
      },
    });

    // Reingreso de un ex-empleado: la unicidad de userId exige update, no create.
    const existingMembership = await tx.caregiverStaffMember.findUnique({ where: { userId: user.id } });
    if (existingMembership) {
      await tx.caregiverStaffMember.update({
        where: { userId: user.id },
        data: {
          caregiverProfileId: invite.caregiverProfileId,
          status: 'ACTIVE',
          invitedByUserId: invite.createdByUserId,
          invitedAt: now,
          joinedAt: now,
          removedAt: null,
          removedByUserId: null,
          removalReason: null,
        },
      });
    } else {
      await tx.caregiverStaffMember.create({
        data: {
          caregiverProfileId: invite.caregiverProfileId,
          userId: user.id,
          status: 'ACTIVE',
          invitedByUserId: invite.createdByUserId,
          joinedAt: now,
        },
      });
    }

    await tx.caregiverStaffInvite.update({
      where: { id: invite.id },
      data: { status: 'USED', usedAt: now, usedByUserId: user.id },
    });

    return { user };
  });

  const payload: JwtPayload = { userId: user.id, role: user.role };
  const { token: accessToken, expiresIn } = signAccessToken(payload);
  const refreshToken = await createRefreshToken(user.id);

  return {
    accessToken,
    refreshToken,
    expiresIn,
    user: { id: user.id, email: user.email, role: user.role, firstName: user.firstName, lastName: user.lastName },
    isCaregiverStaff: true,
    staffCompanyName: invite.caregiverProfile.companyName,
  };
}

/** Resolver central — consulta fresca en cada request, nunca cacheada. */
export async function getStaffContext(staffUserId: string): Promise<StaffContext | null> {
  const membership = await prisma.caregiverStaffMember.findUnique({
    where: { userId: staffUserId },
    include: { caregiverProfile: { select: { id: true, companyName: true, userId: true } } },
  });
  if (!membership || membership.status !== 'ACTIVE') return null;
  return {
    caregiverProfileId: membership.caregiverProfileId,
    ownerUserId: membership.caregiverProfile.userId,
    companyName: membership.caregiverProfile.companyName,
    staffMemberId: membership.id,
  };
}

/** Wrapper fino para auth.service.ts login() — solo se llama para role=CAREGIVER. */
export async function getStaffLoginInfo(userId: string): Promise<{ isCaregiverStaff: boolean; staffCompanyName: string | null }> {
  const ctx = await getStaffContext(userId);
  return { isCaregiverStaff: !!ctx, staffCompanyName: ctx?.companyName ?? null };
}
