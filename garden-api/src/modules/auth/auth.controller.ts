import { Request, Response } from 'express';
import { ZodError } from 'zod';
import prisma from '../../config/database.js';
import { auditLog } from '../../services/audit.service.js';
import * as authService from './auth.service.js';
import * as userService from '../user-service/user.service.js';
import {
  loginSchema,
  registerCaregiverSchema,
  registerClientSchema,
  patchCaregiverProfileSchema,
  type RegisterCaregiverBody,
  type RegisterClientBody,
} from './auth.validation.js';
import { asyncHandler } from '../../shared/async-handler.js';
import { ConflictError, BadRequestError, UnauthorizedError } from '../../shared/errors.js';
import logger from '../../shared/logger.js';
import bcrypt from 'bcrypt';

/** GET /api/auth/me - Usuario actual (requiere Bearer). */
export const me = asyncHandler(async (req: Request, res: Response) => {
  const userId = req.user?.userId ?? (req.user as { id?: string })?.id;
  if (!req.user || !userId) {
    return res.status(401).json({
      success: false,
      error: { code: 'UNAUTHORIZED', message: 'No autenticado' },
    });
  }

  try {
    const user = await userService.getById(userId);
    if (!user) {
      // Si el token es válido pero el usuario no existe, es un caso de sesión inválida
      logger.warn('GET /api/auth/me: Usuario no encontrado', { userId });
      return res.status(401).json({
        success: false,
        error: { code: 'USER_NOT_FOUND', message: 'Usuario no encontrado' }
      });
    }
    // Para CLIENT, incluir clientProfile con datos extendidos
    if (user.role === 'CLIENT') {
      const clientProfile = await prisma.clientProfile.findUnique({
        where: { userId: user.id },
        select: {
          isComplete: true,
          address: true,
          bio: true,
          addressLat: true,
          addressLng: true,
          addressStreet: true,
          addressNumber: true,
          addressApartment: true,
          addressCondominio: true,
          addressReference: true,
          addressZone: true,
        },
      });
      return res.json({
        success: true,
        data: {
          ...user,
          address: clientProfile?.address ?? null,
          bio: clientProfile?.bio ?? null,
          addressLat: clientProfile?.addressLat ?? null,
          addressLng: clientProfile?.addressLng ?? null,
          addressStreet: clientProfile?.addressStreet ?? null,
          addressNumber: clientProfile?.addressNumber ?? null,
          addressApartment: clientProfile?.addressApartment ?? null,
          addressCondominio: clientProfile?.addressCondominio ?? null,
          addressReference: clientProfile?.addressReference ?? null,
          addressZone: clientProfile?.addressZone ?? null,
          clientProfile: clientProfile ? { isComplete: clientProfile.isComplete } : null,
        },
      });
    }

    // Para CAREGIVER, el profilePicture principal puede estar en CaregiverProfile.profilePhoto
    if (user.role === 'CAREGIVER') {
      const caregiverProfile = await prisma.caregiverProfile.findUnique({
        where: { userId: user.id },
        select: { profilePhoto: true },
      });
      // Priorizar profilePhoto si existe y user.profilePicture es null
      const effectivePhoto = user.profilePicture || caregiverProfile?.profilePhoto;
      return res.json({
        success: true,
        data: { 
          ...user, 
          profilePicture: effectivePhoto,
          caregiverProfile: caregiverProfile ? { profilePhoto: caregiverProfile.profilePhoto } : null 
        },
      });
    }
    return res.json({ success: true, data: user });
  } catch (error) {
    // Log del error real para debugging
    logger.error('Error en GET /api/auth/me', { 
      error: error instanceof Error ? error.message : String(error),
      stack: error instanceof Error ? error.stack : undefined,
      userId 
    });
    // Devolver error genérico sin exponer detalles internos
    return res.status(500).json({ 
      success: false, 
      error: { code: 'INTERNAL_ERROR', message: 'Error al obtener información del usuario' } 
    });
  }
});

/** POST /api/auth/caregiver/register - Registro cuidador (full submit). */
export const registerCaregiver = asyncHandler(async (req: Request, res: Response) => {
  const { getBoolSetting } = await import('../../utils/settings-cache.js');
  if (!await getBoolSetting('newRegistrationsEnabled', true)) {
    return res.status(403).json({
      success: false,
      error: { code: 'REGISTRATIONS_DISABLED', message: 'Los registros están temporalmente deshabilitados.' },
    });
  }
  const files = req.files as Express.Multer.File[] | undefined;
  const safeBody = req.body
    ? {
        ...req.body,
        user: req.body.user
          ? { ...req.body.user, password: req.body.user.password != null ? '[REDACTED]' : undefined }
          : req.body.user,
      }
    : req.body;
  logger.info('Intento registro cuidador – body + files', {
    body: safeBody,
    files: files?.map((f) => ({ fieldname: f.fieldname, originalname: f.originalname })) ?? undefined,
  });

  let body: RegisterCaregiverBody;
  try {
    body = registerCaregiverSchema.parse(req.body);
  } catch (err) {
    if (err instanceof ZodError) {
      const issues = err.issues.map((issue) => ({
        field: issue.path.join('.'),
        message: issue.message,
      }));
      logger.warn('Registro cuidador – validación fallida', { issues });
      return res.status(400).json({
        success: false,
        message: 'Datos inválidos',
        error: { code: 'VALIDATION_ERROR', message: 'Datos inválidos' },
        errors: issues,
      });
    }
    throw err;
  }

  const result = await authService.registerCaregiver(body);
  auditLog({ userId: result.user.id, action: 'USER_REGISTERED', entity: 'User', entityId: result.user.id, details: { role: 'CAREGIVER' }, ip: req.ip });
  res.status(201).json({
    success: true,
    data: {
      user: result.user,
      profileId: result.profileId,
      verificationStatus: result.verificationStatus,
      accessToken: result.accessToken,
      expiresIn: result.expiresIn,
    },
  });
});

/** POST /api/auth/client/register - Registro cliente (dueño de mascota). Role siempre CLIENT en backend. */
export const registerClient = asyncHandler(async (req: Request, res: Response) => {
  const { getBoolSetting } = await import('../../utils/settings-cache.js');
  if (!await getBoolSetting('newRegistrationsEnabled', true)) {
    return res.status(403).json({
      success: false,
      error: { code: 'REGISTRATIONS_DISABLED', message: 'Los registros están temporalmente deshabilitados.' },
    });
  }
  const safeBody = req.body
    ? {
        ...req.body,
        password: req.body.password != null ? '[REDACTED]' : undefined,
      }
    : req.body;
  logger.info('Intento registro cliente – body recibido', { body: safeBody });

  let body: RegisterClientBody;
  try {
    body = registerClientSchema.parse(req.body);
  } catch (err) {
    if (err instanceof ZodError) {
      const issues = err.issues.map((issue) => ({
        field: issue.path.join('.'),
        message: issue.message,
      }));
      logger.warn('Registro cliente – validación fallida', { issues });
      return res.status(400).json({
        success: false,
        message: 'Datos inválidos',
        errors: issues,
      });
    }
    throw err;
  }

  logger.info('Validación pasada, datos:', {
    firstName: body.firstName,
    lastName: body.lastName,
    email: body.email,
    phone: body.phone,
    address: body.address ?? null,
  });

  try {
    const result = await authService.registerClient(body);
    auditLog({ userId: result.user.id, action: 'USER_REGISTERED', entity: 'User', entityId: result.user.id, details: { role: 'CLIENT' }, ip: req.ip });
    return res.status(201).json({
      success: true,
      data: {
        user: result.user,
        profileId: result.profileId,
        accessToken: result.accessToken,
        expiresIn: result.expiresIn,
      },
    });
  } catch (err) {
    if (err instanceof ConflictError) {
      throw err;
    }
    const errMessage = err instanceof Error ? err.message : String(err);
    const errObj = err && typeof err === 'object' ? (err as Record<string, unknown>) : {};
    logger.error('Error al registrar cliente (controller)', {
      message: errMessage,
      code: errObj.code,
      meta: errObj.meta,
      stack: err instanceof Error ? err.stack : undefined,
      input: {
        email: req.body?.email,
        phone: req.body?.phone ? `***${String(req.body.phone).slice(-4)}` : undefined,
        firstName: req.body?.firstName ? String(req.body.firstName) : undefined,
      },
    });
    return res.status(500).json({
      success: false,
      message: errMessage || 'Error interno al registrar. Intenta más tarde.',
      error: {
        code: 'INTERNAL_ERROR',
        message: errMessage || 'Error interno al registrar. Intenta más tarde.',
      },
    });
  }
});

/** GET /api/auth/check-email?email=xxx - Verifica si el email existe. Para flujo email-first login. */
export const checkEmail = asyncHandler(async (req: Request, res: Response) => {
  const email = req.query.email;
  if (typeof email !== 'string' || !email.trim()) {
    return res.status(400).json({ success: false, error: { message: 'Email requerido' } });
  }
  const user = await prisma.user.findUnique({
    where: { email: email.toLowerCase().trim() },
    select: { id: true },
  });
  res.json({ success: true, data: { exists: !!user } });
});

/** POST /api/auth/login - Login. Opcional: ?role=caregiver para exigir role CAREGIVER. */
export const login = asyncHandler(async (req: Request, res: Response) => {
  const body = loginSchema.parse(req.body);
  const roleFilter = req.query.role === 'caregiver' ? 'CAREGIVER' : undefined;
  const result = await authService.login(body, roleFilter);
  res.json({
    success: true,
    data: {
      accessToken: result.accessToken,
      expiresIn: result.expiresIn,
      user: result.user,
    },
  });
});

/** POST /api/auth/send-verification-email — generate 6-digit code, send real email (10 min expiry). */
export const sendVerificationEmail = asyncHandler(async (req: Request, res: Response) => {
  const userId = req.user!.userId;
  const emailService = await import('./email.service.js');
  const result = await emailService.generateAndSendVerificationCode(userId);
  res.json({ success: true, data: result });
});

/** POST /api/auth/verify-email — body: { code }. Validate code, mark user + caregiver email verified. */
export const verifyEmail = asyncHandler(async (req: Request, res: Response) => {
  const userId = req.user!.userId;
  const { code } = req.body as { code?: string };
  if (!code || typeof code !== 'string') {
    return res.status(400).json({
      success: false,
      error: { code: 'MISSING_CODE', message: 'Código requerido' },
    });
  }
  const emailService = await import('./email.service.js');
  const result = await emailService.verifyCode(userId, code);
  res.json({ success: true, data: result });
});

/** PATCH /api/auth/me - Actualizar datos personales del usuario. */
export const patchMe = asyncHandler(async (req: Request, res: Response) => {
  const userId = req.user!.userId;
  const {
    firstName, lastName, phone, city, country, dateOfBirth, address, bio, email,
    addressLat, addressLng, addressStreet, addressNumber, addressApartment,
    addressCondominio, addressReference, addressZone,
  } = req.body as {
    firstName?: string; lastName?: string; phone?: string; city?: string; country?: string;
    dateOfBirth?: string; address?: string; bio?: string; email?: string;
    addressLat?: number; addressLng?: number;
    addressStreet?: string; addressNumber?: string; addressApartment?: string;
    addressCondominio?: string; addressReference?: string; addressZone?: string;
  };
  const userData: Record<string, unknown> = {};
  if (firstName && firstName.trim()) userData.firstName = firstName.trim();
  if (lastName && lastName.trim()) userData.lastName = lastName.trim();
  if (phone && phone.trim()) userData.phone = phone.trim();
  if (city !== undefined) userData.city = city?.trim() || null;
  if (country !== undefined) userData.country = country?.trim() || null;
  if (dateOfBirth !== undefined) {
    const d = new Date(dateOfBirth);
    if (!isNaN(d.getTime())) userData.dateOfBirth = d;
  }
  if (email && email.trim()) {
    const newEmail = email.trim().toLowerCase();
    const currentUser = await prisma.user.findUnique({ where: { id: userId }, select: { emailVerified: true } });
    if (currentUser?.emailVerified) {
      return res.status(400).json({ success: false, error: { code: 'EMAIL_ALREADY_VERIFIED', message: 'No puedes cambiar un correo ya verificado' } });
    }
    const existing = await prisma.user.findUnique({ where: { email: newEmail } });
    if (existing && existing.id !== userId) {
      return res.status(409).json({ success: false, error: { code: 'EMAIL_IN_USE', message: 'Ese correo ya está registrado' } });
    }
    userData.email = newEmail;
  }

  const profileData: Record<string, unknown> = {};
  if (address !== undefined) profileData.address = address?.trim() || null;
  if (bio !== undefined) profileData.bio = bio?.trim() || null;
  if (addressLat !== undefined) profileData.addressLat = addressLat ?? null;
  if (addressLng !== undefined) profileData.addressLng = addressLng ?? null;
  if (addressStreet !== undefined) profileData.addressStreet = addressStreet?.trim() || null;
  if (addressNumber !== undefined) profileData.addressNumber = addressNumber?.trim() || null;
  if (addressApartment !== undefined) profileData.addressApartment = addressApartment?.trim() || null;
  if (addressCondominio !== undefined) profileData.addressCondominio = addressCondominio?.trim() || null;
  if (addressReference !== undefined) profileData.addressReference = addressReference?.trim() || null;
  if (addressZone !== undefined) profileData.addressZone = addressZone?.trim() || null;

  if (Object.keys(userData).length === 0 && Object.keys(profileData).length === 0) {
    return res.status(400).json({ success: false, error: { code: 'EMPTY_BODY', message: 'Nada que actualizar' } });
  }

  let updated: { firstName: string; lastName: string; phone: string; city: string | null; country: string | null; dateOfBirth: Date | null } | null = null;
  if (Object.keys(userData).length > 0) {
    updated = await prisma.user.update({ where: { id: userId }, data: userData });
  }
  if (Object.keys(profileData).length > 0) {
    await prisma.clientProfile.upsert({
      where: { userId },
      update: profileData,
      create: { userId, ...profileData },
    });
  }

  const freshUser = await prisma.user.findUnique({
    where: { id: userId },
    select: { firstName: true, lastName: true, phone: true, city: true, country: true, dateOfBirth: true },
  });
  const freshProfile = await prisma.clientProfile.findUnique({
    where: { userId },
    select: { address: true, bio: true },
  });
  res.json({ success: true, data: {
    firstName: freshUser?.firstName,
    lastName: freshUser?.lastName,
    phone: freshUser?.phone,
    city: freshUser?.city,
    country: freshUser?.country,
    dateOfBirth: freshUser?.dateOfBirth,
    address: freshProfile?.address ?? null,
    bio: freshProfile?.bio ?? null,
  }});
});

/** PATCH /api/caregiver/profile - Actualizar perfil del cuidador (solo logueado). */
export const patchProfile = asyncHandler(async (req: Request, res: Response) => {
  const userId = req.user!.userId;
  const body = patchCaregiverProfileSchema.parse(req.body);
  const result = await authService.updateCaregiverProfile(userId, body);
  res.json({ success: true, data: result });
});

/** DELETE /api/auth/account — soft-delete: anonymize auth data, transfer balance to Garden, keep history */
export const deleteAccount = asyncHandler(async (req: Request, res: Response) => {
  const userId = req.user?.userId ?? (req.user as { id?: string })?.id;
  if (!userId) return res.status(401).json({ success: false, error: { code: 'UNAUTHORIZED', message: 'No autenticado' } });

  const { password } = req.body;
  if (!password) return res.status(400).json({ success: false, error: { code: 'MISSING_PASSWORD', message: 'Contraseña requerida' } });

  // 1. Load user
  const user = await prisma.user.findUnique({ where: { id: userId } });
  if (!user) return res.status(404).json({ success: false, error: { code: 'NOT_FOUND', message: 'Usuario no encontrado' } });

  // 2. Verify password
  const bcrypt = await import('bcrypt');
  const valid = await bcrypt.default.compare(password, user.passwordHash);
  if (!valid) return res.status(400).json({ success: false, error: { code: 'WRONG_PASSWORD', message: 'Contraseña incorrecta' } });

  // 3. Check for pending obligations
  const pendingBookings = await prisma.booking.count({
    where: {
      OR: [
        { clientId: userId, status: { in: ['PENDING_PAYMENT', 'PAYMENT_PENDING_APPROVAL', 'WAITING_CAREGIVER_APPROVAL', 'CONFIRMED', 'IN_PROGRESS'] } },
      ],
    },
  });

  // For caregiver: check their bookings too
  let caregiverPendingBookings = 0;
  let caregiverBalance = 0;
  const caregiverProfile = await prisma.caregiverProfile.findUnique({ where: { userId } });
  if (caregiverProfile) {
    caregiverPendingBookings = await prisma.booking.count({
      where: {
        caregiverId: caregiverProfile.id,
        status: { in: ['CONFIRMED', 'IN_PROGRESS', 'PENDING_PAYMENT', 'PAYMENT_PENDING_APPROVAL', 'WAITING_CAREGIVER_APPROVAL'] },
      },
    });
    caregiverBalance = Number(caregiverProfile.balance ?? 0);
  }

  const clientProfile = await prisma.clientProfile.findUnique({ where: { userId } });
  const clientBalance = Number(clientProfile?.balance ?? 0);

  const pendingDisputes = await (prisma as any).dispute?.count?.({
    where: { status: { in: ['OPEN', 'IN_REVIEW'] }, booking: { OR: [{ clientId: userId }, ...(caregiverProfile ? [{ caregiverId: caregiverProfile.id }] : [])] } },
  }).catch(() => 0) ?? 0;

  if (pendingBookings + caregiverPendingBookings > 0) {
    return res.status(400).json({
      success: false,
      error: { code: 'PENDING_BOOKINGS', message: 'Tienes reservas activas o pendientes. Debes esperar a que finalicen antes de eliminar tu cuenta.' },
    });
  }
  if (pendingDisputes > 0) {
    return res.status(400).json({
      success: false,
      error: { code: 'PENDING_DISPUTES', message: 'Tienes disputas abiertas. Debes esperar a que se resuelvan.' },
    });
  }

  // 4. Transfer wallet balance to Garden (create an outgoing transaction)
  if (caregiverBalance > 0) {
    await prisma.walletTransaction.create({
      data: {
        userId,
        type: 'WITHDRAWAL',
        amount: caregiverProfile!.balance,
        balance: 0,
        description: 'Saldo transferido a GARDEN al eliminar cuenta',
        status: 'COMPLETED',
      },
    });
    await prisma.caregiverProfile.update({ where: { userId }, data: { balance: 0 } });
  }
  if (clientBalance > 0) {
    await prisma.walletTransaction.create({
      data: {
        userId,
        type: 'WITHDRAWAL',
        amount: clientProfile!.balance,
        balance: 0,
        description: 'Saldo transferido a GARDEN al eliminar cuenta',
        status: 'COMPLETED',
      },
    });
    await prisma.clientProfile.update({ where: { userId }, data: { balance: 0 } });
  }

  // 5. Soft-delete: anonymize user data so they can re-register with same email
  const deletedTag = `deleted_${Date.now()}`;
  await prisma.user.update({
    where: { id: userId },
    data: {
      email: `${deletedTag}@garden.deleted`,
      passwordHash: '',
      phone: `${deletedTag}`,
      isDeleted: true,
      deletedAt: new Date(),
    },
  });

  // 6. Remove from marketplace if caregiver
  if (caregiverProfile) {
    await prisma.caregiverProfile.update({
      where: { userId },
      data: { status: 'DRAFT', suspended: true },
    });
  }

  logger.info('Account deleted (soft)', { userId, role: user.role });

  res.json({ success: true, data: { message: 'Cuenta eliminada correctamente' } });
});

/** PUT /api/auth/fcm-token — saves or updates the FCM device token for push notifications. */
export const updateFcmToken = asyncHandler(async (req: Request, res: Response) => {
  const userId = req.user!.userId;
  const { fcmToken } = req.body as { fcmToken?: string };

  if (!fcmToken || typeof fcmToken !== 'string') {
    res.status(400).json({ success: false, error: 'fcmToken is required' });
    return;
  }

  await prisma.user.update({
    where: { id: userId },
    data: { fcmToken },
  });

  res.json({ success: true });
});

/**
 * POST /api/auth/refresh
 * Rota el refresh token y devuelve un nuevo access token + nuevo refresh token.
 * El token anterior queda revocado inmediatamente.
 * Body: { refreshToken: string }
 */
export const refreshToken = asyncHandler(async (req: Request, res: Response) => {
  const { refreshToken: raw } = req.body as { refreshToken?: string };

  if (!raw || typeof raw !== 'string') {
    res.status(400).json({
      success: false,
      error: { code: 'MISSING_REFRESH_TOKEN', message: 'Se requiere el campo refreshToken.' },
    });
    return;
  }

  const result = await authService.rotateRefreshToken(raw);

  if (!result) {
    res.status(401).json({
      success: false,
      error: { code: 'INVALID_REFRESH_TOKEN', message: 'Token inválido, expirado o ya utilizado. Inicia sesión de nuevo.' },
    });
    return;
  }

  res.json({
    success: true,
    data: {
      accessToken: result.accessToken,
      refreshToken: result.refreshToken,
      expiresIn: result.expiresIn,
    },
  });
});

/**
 * POST /api/auth/logout
 * 1. Revoca todos los refresh tokens activos del usuario.
 * 2. Añade el access token actual a la blacklist hasta que expire.
 *    Esto garantiza que el token no pueda usarse después del logout
 *    incluso dentro de su ventana de validez (7 días sin blacklist).
 */
export const logout = asyncHandler(async (req: Request, res: Response) => {
  const userId = req.user!.userId;
  const rawToken = (req.headers.authorization ?? '').slice(7); // strip "Bearer "

  const { blacklistToken } = await import('../../services/token-blacklist.service.js');
  await Promise.all([
    authService.revokeAllRefreshTokens(userId),
    blacklistToken(rawToken),
  ]);

  logger.info('User logged out — refresh tokens revoked + access token blacklisted', { userId });
  res.json({ success: true, data: { message: 'Sesión cerrada correctamente.' } });
});


/**
 * POST /api/auth/switch-role
 * Cambia el rol activo en sesión. Body: { targetRole: 'CLIENT' | 'CAREGIVER' }
 * Devuelve nuevos tokens con el rol activo incluido en el payload.
 */
export const switchRole = asyncHandler(async (req: Request, res: Response) => {
  const userId = req.user!.userId;
  const { targetRole } = req.body as { targetRole?: string };

  if (!targetRole || !['CLIENT', 'CAREGIVER'].includes(targetRole)) {
    return res.status(400).json({
      success: false,
      error: { code: 'INVALID_ROLE', message: 'targetRole debe ser CLIENT o CAREGIVER.' },
    });
  }

  const result = await authService.switchRole(userId, targetRole as 'CLIENT' | 'CAREGIVER');

  res.json({
    success: true,
    data: {
      accessToken: result.accessToken,
      refreshToken: result.refreshToken,
      expiresIn: result.expiresIn,
      activeRole: result.activeRole,
    },
  });
});

/**
 * POST /api/auth/init-caregiver-profile
 * Convierte una cuenta CLIENT en CAREGIVER creando un CaregiverProfile vacío.
 * Devuelve nuevos tokens con role=CAREGIVER.
 */
export const initCaregiverProfile = asyncHandler(async (req: Request, res: Response) => {
  const userId = req.user!.userId;
  const result = await authService.initCaregiverProfile(userId);
  res.json({
    success: true,
    data: {
      accessToken: result.accessToken,
      refreshToken: result.refreshToken,
      expiresIn: result.expiresIn,
    },
  });
});

/**
 * POST /api/auth/abandon-caregiver-profile
 * Revierte la conversión CLIENT→CAREGIVER. Solo funciona si el perfil está en DRAFT.
 */
export const abandonCaregiverProfile = asyncHandler(async (req: Request, res: Response) => {
  const userId = req.user!.userId;
  const result = await authService.abandonCaregiverProfile(userId);
  res.json({
    success: true,
    data: {
      accessToken: result.accessToken,
      refreshToken: result.refreshToken,
      expiresIn: result.expiresIn,
    },
  });
});

// ── Change Password (authenticated) ──────────────────────────────────────────

/**
 * PATCH /api/auth/change-password
 * Body: { currentPassword, newPassword, confirmPassword? }
 * Requires valid Bearer token. Revokes all other sessions on success.
 */
export const changePassword = asyncHandler(async (req: Request, res: Response) => {
  const userId = req.user!.userId;
  const { currentPassword, newPassword, confirmPassword } = req.body ?? {};

  if (!currentPassword || typeof currentPassword !== 'string') {
    throw new BadRequestError('La contraseña actual es requerida.', 'MISSING_CURRENT_PASSWORD');
  }
  if (!newPassword || typeof newPassword !== 'string') {
    throw new BadRequestError('La nueva contraseña es requerida.', 'MISSING_NEW_PASSWORD');
  }
  if (newPassword.length < 8) {
    throw new BadRequestError('La nueva contraseña debe tener al menos 8 caracteres.', 'PASSWORD_TOO_SHORT');
  }
  if (newPassword.length > 128) {
    throw new BadRequestError('La contraseña no puede superar 128 caracteres.', 'PASSWORD_TOO_LONG');
  }
  if (confirmPassword !== undefined && newPassword !== confirmPassword) {
    throw new BadRequestError('Las contraseñas no coinciden.', 'PASSWORD_MISMATCH');
  }

  const user = await prisma.user.findUnique({
    where: { id: userId, isDeleted: false },
    select: { id: true, passwordHash: true },
  });

  if (!user) throw new UnauthorizedError('Usuario no encontrado.');

  const currentMatches = await bcrypt.compare(currentPassword, user.passwordHash);
  if (!currentMatches) {
    throw new UnauthorizedError('La contraseña actual es incorrecta.');
  }

  const isSamePassword = await bcrypt.compare(newPassword, user.passwordHash);
  if (isSamePassword) {
    throw new BadRequestError('La nueva contraseña no puede ser igual a la actual.', 'SAME_PASSWORD');
  }

  const passwordHash = await bcrypt.hash(newPassword, 12);
  const now = new Date();

  await prisma.$transaction([
    prisma.user.update({ where: { id: userId }, data: { passwordHash } }),
    // Revoke all refresh tokens so all other sessions are logged out
    prisma.refreshToken.updateMany({
      where: { userId, revokedAt: null },
      data: { revokedAt: now },
    }),
  ]);

  logger.info(`Password changed for userId=${userId}`);
  res.json({ success: true, message: 'Contraseña actualizada correctamente. Tus otras sesiones han sido cerradas.' });
});

// ── Password Reset ────────────────────────────────────────────────────────────
import * as passwordResetService from './password-reset.service.js';

/**
 * POST /api/auth/forgot-password
 * Body: { email }
 * Always returns 200 to prevent user enumeration.
 */
export const forgotPassword = asyncHandler(async (req: Request, res: Response) => {
  const email = req.body?.email;
  if (!email || typeof email !== 'string') {
    return res.status(400).json({ success: false, error: { code: 'MISSING_EMAIL', message: 'El correo es requerido.' } });
  }
  // Service intentionally swallows "user not found" — same response always
  await passwordResetService.requestPasswordReset(email);
  res.json({ success: true, message: 'Si el correo existe en nuestro sistema, recibirás un enlace de recuperación en los próximos minutos.' });
});

/**
 * GET /api/auth/validate-reset-token?token=<raw>
 * Validates a password reset token before showing the form.
 */
export const validateResetToken = asyncHandler(async (req: Request, res: Response) => {
  const token = req.query.token as string;
  if (!token) {
    return res.status(400).json({ success: false, error: { code: 'MISSING_TOKEN', message: 'Token requerido.' } });
  }
  const data = await passwordResetService.validateResetToken(token);
  res.json({ success: true, data: { email: data.email } });
});

/**
 * POST /api/auth/reset-password
 * Body: { token, password, confirmPassword }
 */
export const resetPassword = asyncHandler(async (req: Request, res: Response) => {
  const { token, password, confirmPassword } = req.body ?? {};
  if (!token) {
    return res.status(400).json({ success: false, error: { code: 'MISSING_TOKEN', message: 'Token requerido.' } });
  }
  if (!password) {
    return res.status(400).json({ success: false, error: { code: 'MISSING_PASSWORD', message: 'La contraseña es requerida.' } });
  }
  if (password !== confirmPassword) {
    return res.status(400).json({ success: false, error: { code: 'PASSWORD_MISMATCH', message: 'Las contraseñas no coinciden.' } });
  }
  await passwordResetService.resetPassword(token, password);
  res.json({ success: true, message: '¡Contraseña restablecida! Ahora puedes iniciar sesión.' });
});

/** POST /api/auth/validate-professional-code — verifica el código de registro profesional sin crear nada. */
export const validateProfessionalCode = asyncHandler(async (req: Request, res: Response) => {
  const { code } = req.body ?? {};
  if (!code || typeof code !== 'string') {
    return res.status(400).json({ success: false, error: { code: 'MISSING_CODE', message: 'Código requerido.' } });
  }
  const valid = await authService.validateProfessionalCode(code);
  if (!valid) {
    return res.status(400).json({ success: false, error: { code: 'INVALID_PROFESSIONAL_CODE', message: 'Código de registro profesional inválido.' } });
  }
  return res.json({ success: true, data: { valid: true } });
});

/** POST /api/auth/register-professional — registro de cuidador profesional con código. */
export const registerProfessional = asyncHandler(async (req: Request, res: Response) => {
  const body = req.body ?? {};
  if (!body.code || typeof body.code !== 'string') {
    return res.status(400).json({ success: false, error: { code: 'MISSING_CODE', message: 'Código de registro requerido.' } });
  }
  if (!body.email || !body.password || !body.firstName || !body.lastName || !body.phone) {
    return res.status(400).json({ success: false, error: { code: 'MISSING_FIELDS', message: 'Faltan campos obligatorios.' } });
  }
  const result = await authService.registerProfessional(body);
  return res.status(201).json({ success: true, data: result });
});

// ── Phone Verification (Firebase Phone Auth) ──────────────────────────────────

/** POST /api/auth/caregiver/verify-phone — body: { firebaseIdToken }.
 *  Verifica el token de Firebase Phone Auth, confirma que el número coincide,
 *  y marca phoneVerified=true en CaregiverProfile. Solo aplica a cuidadores nuevos. */
export const verifyCaregiverPhone = asyncHandler(async (req: Request, res: Response) => {
  const userId = req.user!.userId;
  const { firebaseIdToken } = req.body ?? {};

  if (!firebaseIdToken || typeof firebaseIdToken !== 'string') {
    return res.status(400).json({ success: false, error: { code: 'MISSING_TOKEN', message: 'firebaseIdToken es requerido.' } });
  }

  // Verificar token con Firebase Admin
  const { default: admin } = await import('firebase-admin');
  const projectId = process.env.FIREBASE_PROJECT_ID;
  const privateKey = process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n');
  const clientEmail = process.env.FIREBASE_CLIENT_EMAIL;

  if (!projectId || !privateKey || !clientEmail) {
    return res.status(503).json({ success: false, error: { code: 'FIREBASE_NOT_CONFIGURED', message: 'Firebase no configurado en el servidor.' } });
  }

  if (!admin.apps.length) {
    admin.initializeApp({ credential: admin.credential.cert({ projectId, privateKey, clientEmail } as any) });
  }

  let decoded: any;
  try {
    decoded = await admin.auth().verifyIdToken(firebaseIdToken);
  } catch {
    return res.status(401).json({ success: false, error: { code: 'INVALID_FIREBASE_TOKEN', message: 'Token de Firebase inválido o expirado.' } });
  }

  // El token de Phone Auth incluye `phone_number` (ej: "+59176543210")
  const firebasePhone = decoded.phone_number as string | undefined;
  if (!firebasePhone) {
    return res.status(400).json({ success: false, error: { code: 'NOT_PHONE_TOKEN', message: 'El token no corresponde a verificación de teléfono.' } });
  }

  // Confirmar que el número verificado coincide con el del usuario (ignorando espacios y prefijo)
  const user = await prisma.user.findUnique({ where: { id: userId }, select: { phone: true } });
  if (!user) return res.status(404).json({ success: false, error: { code: 'USER_NOT_FOUND', message: 'Usuario no encontrado.' } });

  const normalizePhone = (p: string) => p.replace(/\D/g, '').replace(/^591/, '');
  if (normalizePhone(firebasePhone) !== normalizePhone(user.phone)) {
    return res.status(400).json({ success: false, error: { code: 'PHONE_MISMATCH', message: 'El número verificado no coincide con el de tu cuenta.' } });
  }

  await prisma.caregiverProfile.updateMany({
    where: { userId },
    data: { phoneVerified: true },
  });

  return res.json({ success: true, message: '¡Teléfono verificado correctamente!' });
});

// ── Password Reset (in-app code flow) ────────────────────────────────────────

import * as passwordResetCodeService from './password-reset-code.service.js';

/** POST /api/auth/forgot-password/send-code — body: { email }. Envía código de 4 dígitos. Siempre 200. */
export const sendResetCode = asyncHandler(async (req: Request, res: Response) => {
  const email = req.body?.email;
  if (!email || typeof email !== 'string') {
    return res.status(400).json({ success: false, error: { code: 'MISSING_EMAIL', message: 'El correo es requerido.' } });
  }
  await passwordResetCodeService.sendResetCode(email);
  res.json({ success: true, message: 'Si el correo existe, recibirás un código de 4 dígitos en los próximos minutos.' });
});

/** POST /api/auth/forgot-password/verify-code — body: { email, code }. Retorna tempToken si es válido. */
export const verifyResetCode = asyncHandler(async (req: Request, res: Response) => {
  const { email, code } = req.body ?? {};
  if (!email || !code) {
    return res.status(400).json({ success: false, error: { code: 'MISSING_FIELDS', message: 'Correo y código son requeridos.' } });
  }
  const { tempToken } = await passwordResetCodeService.verifyResetCode(email, String(code));
  res.json({ success: true, data: { tempToken } });
});

/** POST /api/auth/forgot-password/set-password — body: { tempToken, newPassword }. Cambia la contraseña. */
export const setNewPassword = asyncHandler(async (req: Request, res: Response) => {
  const { tempToken, newPassword } = req.body ?? {};
  if (!tempToken || !newPassword) {
    return res.status(400).json({ success: false, error: { code: 'MISSING_FIELDS', message: 'Token temporal y nueva contraseña son requeridos.' } });
  }
  await passwordResetCodeService.setNewPassword(tempToken, newPassword);
  res.json({ success: true, message: '¡Contraseña actualizada! Ya puedes iniciar sesión.' });
});
