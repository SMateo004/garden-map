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
import { hashPassword, signAccessToken, createRefreshToken, revokeAllRefreshTokens } from '../auth/auth.service.js';
import { sendPushToUser } from '../../services/firebase.service.js';
import logger from '../../shared/logger.js';
import type { JwtPayload } from '../../middleware/auth.middleware.js';
import type { z } from 'zod';
import type { registerStaffBodySchema } from './caregiver-staff.validation.js';
import { assertFeature, getFeaturesForProfile } from '../business-features/business-features.service.js';

type RegisterStaffBody = z.infer<typeof registerStaffBodySchema>;

export interface StaffContext {
  caregiverProfileId: string;
  ownerUserId: string;
  companyName: string | null;
  staffMemberId: string;
  /** Permisos que dio el dueño. Además del permiso, cada ruta exige su función de negocio. */
  canManageBookings: boolean;
  canChat: boolean;
}

function generateCode(): string {
  // 8 chars alfanuméricos en mayúscula — corto para compartir de palabra/WhatsApp,
  // suficientemente amplio (36^8) para no colisionar en la práctica.
  return randomBytes(6).toString('hex').toUpperCase().slice(0, 8);
}

async function assertIsCompanyOwner(ownerUserId: string) {
  const profile = await prisma.caregiverProfile.findFirst({ where: { userId: ownerUserId } });
  if (!profile) throw new NotFoundError('No tienes un perfil de cuidador');
  if (!profile.isCompany) {
    throw new ForbiddenError('Solo las cuentas empresa pueden tener empleados');
  }
  // FIX (auditoría 2026-09-29, D2): no validaba `suspended` — a diferencia de
  // las reservas reales del marketplace, que sí excluyen perfiles suspendidos
  // (booking.service.ts, `where: { ..., suspended: false }`). Una suspensión
  // de admin (ej. tras un incidente de seguridad) no frenaba la gestión de
  // staff de la empresa: el dueño podía seguir generando invitaciones y
  // sumando empleados nuevos mientras estaba suspendido.
  if (profile.suspended) {
    throw new ForbiddenError('Tu cuenta está suspendida — contacta a soporte para más información.');
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
  throw new BadRequestError('No se pudo generar el código, intenta de nuevo');
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
  const teamEnabled = !!invite && (await getFeaturesForProfile(invite.caregiverProfileId)).STAFF_TEAM;
  const valid = !!invite && teamEnabled && invite.status === 'PENDING' && invite.expiresAt > new Date();
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
    canManageBookings: m.canManageBookings,
    canChat: m.canChat,
  }));
}

/**
 * El dueño da o quita permisos a un empleado. Dar un permiso exige que el admin haya
 * habilitado la función correspondiente para la empresa; quitarlo siempre se puede.
 */
export async function setStaffPermissions(
  ownerUserId: string,
  staffMemberId: string,
  changes: { canManageBookings?: boolean; canChat?: boolean }
): Promise<{ canManageBookings: boolean; canChat: boolean }> {
  const member = await assertOwnsStaffMember(ownerUserId, staffMemberId);
  if (member.status === 'REMOVED') throw new BadRequestError('Ese empleado ya no está en el equipo', 'STAFF_REMOVED');
  if (changes.canManageBookings) await assertFeature(member.caregiverProfileId, 'STAFF_BOOKING_DECISIONS');
  if (changes.canChat) await assertFeature(member.caregiverProfileId, 'STAFF_CLIENT_CHAT');
  const updated = await prisma.caregiverStaffMember.update({
    where: { id: staffMemberId },
    data: changes,
    select: { canManageBookings: true, canChat: true },
  });
  return updated;
}

/** Reservas que todavía se pueden asignar (las terminadas o canceladas ya no). */
const ASSIGNABLE_STATUSES = ['WAITING_CAREGIVER_APPROVAL', 'CONFIRMED', 'IN_PROGRESS'] as const;

/**
 * El dueño asigna una reserva a un empleado activo de su equipo (o la desasigna con null).
 * Avisa al empleado por push. La reserva sigue siendo de la empresa: asignar no cambia
 * quién cobra ni quién puede operarla, solo ordena el trabajo del equipo.
 */
export async function assignBooking(
  ownerUserId: string,
  bookingId: string,
  staffMemberId: string | null
): Promise<{ bookingId: string; assignedStaffMemberId: string | null }> {
  const profile = await assertIsCompanyOwner(ownerUserId);
  const booking = await prisma.booking.findUnique({
    where: { id: bookingId },
    select: { id: true, caregiverId: true, status: true, petName: true, serviceType: true, startDate: true, walkDate: true },
  });
  if (!booking || booking.caregiverId !== profile.id) throw new NotFoundError('Reserva no encontrada');
  if (!(ASSIGNABLE_STATUSES as readonly string[]).includes(booking.status)) {
    throw new BadRequestError('Solo se pueden asignar reservas por aceptar, confirmadas o en curso', 'BOOKING_NOT_ASSIGNABLE');
  }

  let assigneeUserId: string | null = null;
  if (staffMemberId) {
    const member = await prisma.caregiverStaffMember.findUnique({ where: { id: staffMemberId } });
    if (!member || member.caregiverProfileId !== profile.id) throw new NotFoundError('Empleado no encontrado');
    if (member.status !== 'ACTIVE') throw new BadRequestError('Ese empleado no está activo', 'STAFF_NOT_ACTIVE');
    assigneeUserId = member.userId;
  }

  await prisma.booking.update({ where: { id: bookingId }, data: { assignedStaffMemberId: staffMemberId } });

  if (assigneeUserId) {
    const day = booking.walkDate ?? booking.startDate;
    const when = day ? ` el ${day.toISOString().slice(0, 10).split('-').reverse().join('/')}` : '';
    const svc = booking.serviceType === 'PASEO' ? 'Paseo' : booking.serviceType === 'HOSPEDAJE' ? 'Hospedaje' : 'Guardería';
    sendPushToUser(assigneeUserId, 'Te asignaron una reserva', `${svc} de ${booking.petName ?? 'una mascota'}${when}.`, {
      type: 'STAFF_BOOKING',
      bookingId,
    }).catch((err) => logger.warn('[STAFF] push de asignación falló', { bookingId, err }));
  }
  return { bookingId, assignedStaffMemberId: staffMemberId };
}

/**
 * userIds de los empleados activos con un permiso — para avisarles (push) de lo que les toca.
 * Vacío si el admin no habilitó la función para la empresa.
 */
export async function staffUserIdsWithPermission(
  caregiverProfileId: string,
  permission: 'canManageBookings' | 'canChat'
): Promise<string[]> {
  const features = await getFeaturesForProfile(caregiverProfileId);
  const feature = permission === 'canManageBookings' ? features.STAFF_BOOKING_DECISIONS : features.STAFF_CLIENT_CHAT;
  if (!feature) return [];
  const members = await prisma.caregiverStaffMember.findMany({
    where: { caregiverProfileId, status: 'ACTIVE', [permission]: true },
    select: { userId: true },
  });
  return members.map((m) => m.userId);
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
  await unassignOpenBookings(staffMemberId);
}

/** Quien sale del equipo deja libres sus reservas pendientes, para que el dueño las reasigne. */
async function unassignOpenBookings(staffMemberId: string): Promise<void> {
  await prisma.booking.updateMany({
    where: { assignedStaffMemberId: staffMemberId, status: { in: [...ASSIGNABLE_STATUSES] } },
    data: { assignedStaffMemberId: null },
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
  // Un código emitido antes de que el admin apagara el equipo ya no sirve.
  await assertFeature(invite.caregiverProfileId, 'STAFF_TEAM');

  const email = body.email.toLowerCase().trim();
  const [existingEmail, existingPhone] = await Promise.all([
    prisma.user.findUnique({ where: { email } }),
    prisma.user.findUnique({ where: { phone: body.phone } }),
  ]);
  if (existingEmail) throw new ConflictError('Ya existe una cuenta con este email. Inicia sesión y usa "Unirme a un equipo" desde tu perfil.', 'EMAIL_EXISTS', 'email');
  if (existingPhone) throw new ConflictError('Ya existe una cuenta con este teléfono. Inicia sesión y usa "Unirme a un equipo" desde tu perfil.', 'PHONE_EXISTS', 'phone');

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

    // FIX (auditoría 2026-09-29, D1): el chequeo de arriba (líneas 162-171) es
    // una lectura plana FUERA de esta transacción — dos registros casi
    // simultáneos con el mismo código pasan ambos ese chequeo (ninguno
    // comiteó todavía) y, con el `update` incondicional que había acá, ambos
    // terminaban marcando el invite como USED sin error: dos personas quedan
    // como staff ACTIVO de la empresa con el mismo código de un solo uso.
    // `updateMany` condicionado a `status: 'PENDING'` + chequeo de `count` —
    // mismo patrón de claim atómico ya usado en el resto del proyecto
    // (booking.service.ts, payment.service.ts). Si pierde la carrera, el
    // throw revierte TODA la transacción (el User y el CaregiverStaffMember
    // recién creados incluidos).
    const claimed = await tx.caregiverStaffInvite.updateMany({
      where: { id: invite.id, status: 'PENDING' },
      data: { status: 'USED', usedAt: now, usedByUserId: user.id },
    });
    if (claimed.count === 0) {
      throw new BadRequestError('Código de invitación inválido o ya usado', 'INVALID_STAFF_CODE');
    }

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
    include: { caregiverProfile: { select: { id: true, companyName: true, userId: true, suspended: true } } },
  });
  if (!membership || membership.status !== 'ACTIVE') return null;
  // FIX (auditoría 2026-09-29, D2): mismo hueco que assertIsCompanyOwner/
  // resolveCompanyProfile, pero acá importa más — es el gate más temprano de
  // TODAS las rutas de staff (requireStaffMembership). Sin esto, un empleado
  // podía seguir operando el CRM walk-in aunque la cuenta de la empresa
  // estuviera suspendida, mientras los dueños-sin-staff ya quedaban
  // bloqueados en assertIsCompanyOwner.
  if (membership.caregiverProfile.suspended) return null;
  return {
    caregiverProfileId: membership.caregiverProfileId,
    ownerUserId: membership.caregiverProfile.userId,
    companyName: membership.caregiverProfile.companyName,
    staffMemberId: membership.id,
    canManageBookings: membership.canManageBookings,
    canChat: membership.canChat,
  };
}

/** Wrapper fino para auth.service.ts login() — solo se llama para role=CAREGIVER.
 * `hasOwnCaregiverProfile` permite a la app ofrecer el cambio entre "empleado de
 * la empresa" y "cuidador independiente" cuando la misma cuenta tiene ambos. */
export async function getStaffLoginInfo(userId: string): Promise<{
  isCaregiverStaff: boolean;
  staffCompanyName: string | null;
  hasOwnCaregiverProfile: boolean;
}> {
  const [ctx, ownProfile] = await Promise.all([
    getStaffContext(userId),
    prisma.caregiverProfile.findUnique({ where: { userId }, select: { id: true } }),
  ]);
  return { isCaregiverStaff: !!ctx, staffCompanyName: ctx?.companyName ?? null, hasOwnCaregiverProfile: !!ownProfile };
}

/**
 * Un usuario YA logueado (dueño de mascota o cuidador independiente) canjea un
 * código de invitación y se suma al equipo de una empresa SIN crear otra cuenta.
 *
 * - Una cuenta CLIENT pasa a rol CAREGIVER (mismo cambio que hace un registro de
 *   staff nuevo); puede volver a usar la app como dueño con switchRole, y sus
 *   mascotas/perfil de cliente quedan intactos.
 * - Un cuidador independiente conserva su CaregiverProfile y su saldo: los
 *   ingresos como empleado son de la empresa (billetera del dueño), los de su
 *   perfil propio siguen siendo suyos. Cada request opera en UNA sola identidad
 *   (actAsOwner solo corre en /api/caregiver-staff/*), nunca mezcladas.
 * - Una persona pertenece a UNA sola empresa a la vez. Los dueños de empresa no
 *   pueden ser empleados de otra.
 */
export async function joinTeamWithExistingAccount(
  userId: string,
  rawCode: string
): Promise<RegisterStaffResult & { hasOwnCaregiverProfile: boolean }> {
  const code = rawCode.trim().toUpperCase();
  const user = await prisma.user.findUnique({
    where: { id: userId },
    select: { id: true, email: true, role: true, activeRole: true, isDeleted: true, firstName: true, lastName: true },
  });
  if (!user || user.isDeleted) throw new NotFoundError('Usuario no encontrado');
  if (user.role !== UserRole.CLIENT && user.role !== UserRole.CAREGIVER) {
    throw new ForbiddenError('Esta cuenta no puede unirse a un equipo', 'STAFF_JOIN_WRONG_ROLE');
  }

  const ownProfile = await prisma.caregiverProfile.findUnique({ where: { userId }, select: { id: true, isCompany: true } });
  if (ownProfile?.isCompany) {
    throw new ForbiddenError('Una cuenta de empresa no puede ser empleada de otra empresa', 'STAFF_JOIN_COMPANY_OWNER');
  }

  const invite = await prisma.caregiverStaffInvite.findUnique({
    where: { code },
    include: { caregiverProfile: { select: { id: true, companyName: true, userId: true, suspended: true } } },
  });
  if (!invite || invite.status !== 'PENDING') {
    throw new BadRequestError('Código de invitación inválido o ya usado', 'INVALID_STAFF_CODE');
  }
  if (invite.expiresAt <= new Date()) {
    throw new BadRequestError('Ese código de invitación venció', 'STAFF_CODE_EXPIRED');
  }
  await assertFeature(invite.caregiverProfileId, 'STAFF_TEAM');
  if (invite.caregiverProfile.suspended) {
    throw new BadRequestError('Esa empresa no está activa en este momento', 'STAFF_COMPANY_SUSPENDED');
  }
  if (invite.caregiverProfile.userId === userId) {
    throw new BadRequestError('No puedes unirte a tu propio equipo', 'STAFF_JOIN_SELF');
  }

  const now = new Date();
  await prisma.$transaction(async (tx) => {
    // Lock sobre el usuario: dos canjes simultáneos de la misma persona no
    // pueden pasar ambos el chequeo de "no tiene membresía vigente".
    await tx.$queryRaw`SELECT id FROM "users" WHERE id = ${userId} FOR UPDATE`;
    const existing = await tx.caregiverStaffMember.findUnique({ where: { userId } });
    if (existing && existing.status !== 'REMOVED') {
      throw new ConflictError(
        'Ya formas parte del equipo de una empresa. Sal de ese equipo antes de unirte a otro.',
        'ALREADY_STAFF'
      );
    }

    const claimed = await tx.caregiverStaffInvite.updateMany({
      where: { id: invite.id, status: 'PENDING' },
      data: { status: 'USED', usedAt: now, usedByUserId: userId },
    });
    if (claimed.count === 0) {
      throw new BadRequestError('Código de invitación inválido o ya usado', 'INVALID_STAFF_CODE');
    }

    if (existing) {
      // Reingreso de un ex-empleado (userId es único → update, no create).
      await tx.caregiverStaffMember.update({
        where: { userId },
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
          userId,
          status: 'ACTIVE',
          invitedByUserId: invite.createdByUserId,
          joinedAt: now,
        },
      });
    }

    // Siempre rol CAREGIVER y sin rol activo temporal: el empleado entra en su modo
    // de trabajo. Puede volver a modo dueño después con switchRole.
    await tx.user.update({ where: { id: userId }, data: { role: UserRole.CAREGIVER, activeRole: null } });
  });

  // El rol pudo cambiar → tokens nuevos (mismo patrón que switchRole).
  await revokeAllRefreshTokens(userId);
  const newRole = UserRole.CAREGIVER;
  const payload: JwtPayload = { userId, role: newRole };
  const { token: accessToken, expiresIn } = signAccessToken(payload);
  const refreshToken = await createRefreshToken(userId);

  // Avisar al dueño — nunca debe tumbar el canje.
  prisma.notification
    .create({
      data: {
        userId: invite.caregiverProfile.userId,
        type: 'INFO',
        title: 'Nuevo miembro en tu equipo',
        message: `${user.firstName} ${user.lastName} se unió a ${invite.caregiverProfile.companyName ?? 'tu empresa'} con el código ${code}.`,
      },
    })
    .catch((err) => logger.error('No se pudo notificar al dueño del nuevo empleado', { error: (err as Error).message }));
  sendPushToUser(
    invite.caregiverProfile.userId,
    'Nuevo miembro en tu equipo',
    `${user.firstName} ${user.lastName} se unió a tu empresa.`,
    { type: 'STAFF_JOINED' }
  ).catch(() => {});

  return {
    accessToken,
    refreshToken,
    expiresIn,
    user: { id: user.id, email: user.email, role: newRole, firstName: user.firstName, lastName: user.lastName },
    isCaregiverStaff: true,
    staffCompanyName: invite.caregiverProfile.companyName,
    hasOwnCaregiverProfile: !!ownProfile,
  };
}

/** El empleado se sale por su cuenta del equipo. Conserva su cuenta, y su
 * perfil independiente si lo tiene. Queda como REMOVED (mismo estado que si
 * lo hubiera quitado el dueño) para poder reingresar con un código nuevo. */
export async function leaveTeam(userId: string): Promise<void> {
  const member = await prisma.caregiverStaffMember.findUnique({ where: { userId } });
  if (!member || member.status === 'REMOVED') {
    throw new NotFoundError('No formas parte de ningún equipo');
  }
  await prisma.caregiverStaffMember.update({
    where: { userId },
    data: { status: 'REMOVED', removedAt: new Date(), removedByUserId: userId, removalReason: 'Salió del equipo por su cuenta' },
  });
  await unassignOpenBookings(member.id);
}
