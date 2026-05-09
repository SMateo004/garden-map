import type { Request, Response, NextFunction } from 'express';
import { randomBytes } from 'crypto';
import bcrypt from 'bcrypt';
import prisma from '../../config/database.js';
import { signAccessToken, createRefreshToken } from './auth.service.js';
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

/**
 * POST /api/auth/social/register-client
 *
 * Solo para clientes (dueños de mascotas).
 * Recibe datos del proveedor social + phone + dateOfBirth completados a mano.
 * Crea la cuenta y devuelve JWT.
 *
 * Body: {
 *   provider, idToken,
 *   firstName, lastName, phone,
 *   dateOfBirth?: string (YYYY-MM-DD)
 * }
 */
export async function socialRegisterClient(req: Request, res: Response, next: NextFunction) {
  try {
    const { provider, idToken, firstName, lastName, phone, dateOfBirth } =
      req.body as {
        provider: string;
        idToken: string;
        firstName: string;
        lastName: string;
        phone: string;
        dateOfBirth?: string;
      };

    if (!provider || !idToken || !firstName || !lastName || !phone) {
      throw new BadRequestError('Faltan campos requeridos');
    }

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

    // Generar passwordHash aleatorio (cuenta social — sin contraseña manual)
    const randomPassword = randomBytes(32).toString('hex');
    const passwordHash = await bcrypt.hash(randomPassword, 12);

    const user = await prisma.user.create({
      data: {
        email,
        passwordHash,
        role: 'CLIENT',
        firstName: firstName.trim(),
        lastName: lastName.trim(),
        phone: phone.trim(),
        emailVerified: true, // email verificado por el proveedor social
        dateOfBirth: dateOfBirth ? new Date(dateOfBirth) : undefined,
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
