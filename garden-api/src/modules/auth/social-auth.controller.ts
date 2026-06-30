import type { Request, Response, NextFunction } from 'express';
import { randomBytes } from 'crypto';
import bcrypt from 'bcrypt';
import prisma from '../../config/database.js';
import { signAccessToken, createRefreshToken, assertBetaAccess } from './auth.service.js';
import { getBoolSetting } from '../../utils/settings-cache.js';
import { NotFoundError, BadRequestError } from '../../shared/errors.js';
import logger from '../../shared/logger.js';

/** Verifica un Firebase ID token usando firebase-admin y devuelve los claims del usuario. */
async function verifyFirebaseToken(idToken: string): Promise<{
  uid: string;
  email?: string;
  name?: string;
  picture?: string;
  email_verified?: boolean;
}> {
  const projectId = process.env.FIREBASE_PROJECT_ID;
  const privateKey = process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n');
  const clientEmail = process.env.FIREBASE_CLIENT_EMAIL;

  if (!projectId || !privateKey || !clientEmail) {
    throw new BadRequestError('Firebase no configurado en el servidor');
  }

  const { default: admin } = await import('firebase-admin');
  if (!admin.apps.length) {
    admin.initializeApp({
      credential: admin.credential.cert({ projectId, privateKey, clientEmail } as any),
    });
  }

  const decoded = await admin.auth().verifyIdToken(idToken);
  return {
    uid: decoded.uid,
    email: decoded.email,
    name: decoded.name,
    picture: decoded.picture,
    email_verified: decoded.email_verified,
  };
}

/**
 * POST /api/auth/social/login
 *
 * Body: { provider: 'google' | 'apple' | 'facebook', idToken: string }
 *
 * - Si el email existe → login (funciona para CLIENT y CAREGIVER)
 * - Si no existe → 404 con email + nombre para que el cliente pre-llene el register
 */
export async function socialLogin(req: Request, res: Response, next: NextFunction) {
  try {
    const { provider, idToken } = req.body as { provider: string; idToken: string };

    if (!provider || !idToken) {
      throw new BadRequestError('provider e idToken son requeridos');
    }
    if (!['google', 'apple', 'facebook'].includes(provider)) {
      throw new BadRequestError('provider no válido');
    }

    // 1. Verificar token con Firebase Admin
    const claims = await verifyFirebaseToken(idToken);

    if (!claims.email) {
      throw new BadRequestError('El proveedor no devolvió un email. Verifica los permisos de la app.');
    }

    const email = claims.email.toLowerCase().trim();

    // 2. Buscar usuario por email
    const user = await prisma.user.findUnique({
      where: { email },
      select: {
        id: true,
        email: true,
        role: true,
        activeRole: true,
        isDeleted: true,
        firstName: true,
        lastName: true,
        profilePicture: true,
        emailVerified: true,
      },
    });

    if (!user || user.isDeleted) {
      // Usuario no existe — el cliente debe ir al registro
      const nameParts = (claims.name ?? '').trim().split(' ');
      return res.status(404).json({
        success: false,
        error: {
          code: 'USER_NOT_FOUND',
          message: 'No existe una cuenta con este correo. Regístrate primero.',
        },
        data: {
          email,
          firstName: nameParts[0] ?? '',
          lastName: nameParts.slice(1).join(' ') ?? '',
          photoUrl: claims.picture ?? null,
        },
      });
    }

    // 3. Marcar email como verificado si aún no lo está (proveedor social = email verificado)
    if (!user.emailVerified) {
      await prisma.user.update({
        where: { id: user.id },
        data: { emailVerified: true },
      });
    }

    // 4. Emitir nuestros propios JWT
    const payload = { userId: user.id, role: user.role, ...(user.activeRole ? { activeRole: user.activeRole } : {}) };
    const { token: accessToken, expiresIn } = signAccessToken(payload);
    const refreshToken = await createRefreshToken(user.id);

    logger.info(`[SocialAuth] login ${provider} → user ${user.id} (${user.role})`);

    return res.json({
      success: true,
      data: {
        accessToken,
        refreshToken,
        expiresIn,
        user: {
          id: user.id,
          email: user.email,
          role: user.role,
          activeRole: user.activeRole ?? null,
          firstName: user.firstName,
          lastName: user.lastName,
          profilePicture: user.profilePicture,
        },
      },
    });
  } catch (err) {
    next(err);
  }
}

/** Genera un placeholder único para `User.phone` (columna NOT NULL + UNIQUE)
 *  cuando el proveedor social no entrega teléfono. Formato reconocible y que
 *  nunca matchea el regex de teléfono real (8 dígitos, empieza con 6/7), así
 *  `_isClientDataIncomplete` en el frontend lo detecta como "falta completar". */
function generatePendingPhonePlaceholder(): string {
  return `social_pending_${randomBytes(6).toString('hex')}`;
}

/**
 * POST /api/auth/social/register-client
 *
 * Solo para clientes (dueños de mascotas). Crea la cuenta INSTANTÁNEAMENTE
 * con los datos que el proveedor social entregue en ese momento (nombre,
 * apellido, email, foto) — sin pedir teléfono ni fecha de nacimiento.
 * El usuario completa esos datos después desde "Mi Perfil" (resaltado en
 * naranja vía _isClientDataIncomplete) y DEBE completarlos antes de poder
 * reservar (ver gate en booking.service.ts createBooking).
 *
 * Los cuidadores NUNCA pasan por aquí — deben usar el formulario completo
 * (este endpoint siempre crea role=CLIENT).
 *
 * Body: { provider, idToken, inviteCode? }
 */
export async function socialRegisterClient(req: Request, res: Response, next: NextFunction) {
  try {
    // Same gates as POST /api/auth/client/register — social signup must not
    // be a backdoor around "pause new registrations" or beta invite codes.
    if (!await getBoolSetting('newRegistrationsEnabled', true)) {
      return res.status(403).json({
        success: false,
        error: { code: 'REGISTRATIONS_DISABLED', message: 'Los registros están temporalmente deshabilitados.' },
      });
    }

    const { provider, idToken, inviteCode } =
      req.body as { provider: string; idToken: string; inviteCode?: string };

    if (!provider || !idToken) {
      throw new BadRequestError('Faltan campos requeridos');
    }

    await assertBetaAccess(inviteCode);

    const claims = await verifyFirebaseToken(idToken);
    if (!claims.email) {
      throw new BadRequestError('El proveedor no devolvió un email.');
    }

    const email = claims.email.toLowerCase().trim();

    // Si ya existe → responder con error claro
    const existing = await prisma.user.findUnique({ where: { email } });
    if (existing && !existing.isDeleted) {
      throw new BadRequestError('Ya existe una cuenta con este correo. Inicia sesión.');
    }

    // Generar passwordHash aleatorio (cuenta social — sin contraseña manual,
    // la autenticación siempre pasa por el proveedor social vía idToken)
    const randomPassword = randomBytes(32).toString('hex');
    const passwordHash = await bcrypt.hash(randomPassword, 12);

    const nameParts = (claims.name ?? '').trim().split(/\s+/).filter(Boolean);
    const firstName = nameParts[0] ?? 'Usuario';
    const lastName = nameParts.slice(1).join(' ') || '-';

    const user = await prisma.user.create({
      data: {
        email,
        passwordHash,
        role: 'CLIENT',
        firstName,
        lastName,
        phone: generatePendingPhonePlaceholder(), // completado luego en Mi Perfil
        emailVerified: true, // email verificado por el proveedor social
        // dateOfBirth queda null — se completa luego en Mi Perfil
        profilePicture: claims.picture ?? undefined,
      },
    });

    // Crear ClientProfile asociado
    await prisma.clientProfile.create({ data: { userId: user.id } });

    const { token: accessToken, expiresIn } = signAccessToken({ userId: user.id, role: 'CLIENT' });
    const refreshToken = await createRefreshToken(user.id);

    logger.info(`[SocialAuth] register-client ${provider} → user ${user.id}`);

    return res.status(201).json({
      success: true,
      data: {
        accessToken,
        refreshToken,
        expiresIn,
        user: {
          id: user.id,
          email: user.email,
          role: user.role,
          firstName: user.firstName,
          lastName: user.lastName,
          profilePicture: user.profilePicture,
        },
      },
    });
  } catch (err) {
    next(err);
  }
}
