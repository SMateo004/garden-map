import { Request, Response } from 'express';
import { ZodError } from 'zod';
import prisma from '../../config/database.js';
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
import { ConflictError } from '../../shared/errors.js';
import logger from '../../shared/logger.js';

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
    // Para CLIENT, incluir clientProfile.isComplete para redirigir a completar perfil de mascota si aplica
    if (user.role === 'CLIENT') {
      const clientProfile = await prisma.clientProfile.findUnique({
        where: { userId: user.id },
        select: { isComplete: true },
      });
      return res.json({
        success: true,
        data: { ...user, clientProfile: clientProfile ? { isComplete: clientProfile.isComplete } : null },
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

/** PATCH /api/auth/me - Actualizar datos personales del usuario (firstName, lastName, phone, city, country). */
export const patchMe = asyncHandler(async (req: Request, res: Response) => {
  const userId = req.user!.userId;
  const { firstName, lastName, phone, city, country } = req.body as {
    firstName?: string; lastName?: string; phone?: string; city?: string; country?: string;
  };
  const data: Record<string, string | null> = {};
  if (firstName && firstName.trim()) data.firstName = firstName.trim();
  if (lastName && lastName.trim()) data.lastName = lastName.trim();
  if (phone && phone.trim()) data.phone = phone.trim();
  if (city !== undefined) data.city = city?.trim() || null;
  if (country !== undefined) data.country = country?.trim() || null;
  if (Object.keys(data).length === 0) {
    return res.status(400).json({ success: false, error: { code: 'EMPTY_BODY', message: 'Nada que actualizar' } });
  }
  const updated = await prisma.user.update({ where: { id: userId }, data });
  res.json({ success: true, data: {
    firstName: updated.firstName,
    lastName: updated.lastName,
    phone: updated.phone,
    city: updated.city,
    country: updated.country,
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
