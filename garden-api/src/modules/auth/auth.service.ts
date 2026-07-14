import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';
import { createHash } from 'crypto';
import { UserRole, VerificationStatus, CaregiverStatus, Zone } from '@prisma/client';
import { randomBytes } from 'crypto';
import prisma from '../../config/database.js';
import { env } from '../../config/env.js';
import { ConflictError, UnauthorizedError, BadRequestError, ForbiddenError } from '../../shared/errors.js';
import { ensureAbsoluteUrl, ensureAbsoluteUrls } from '../../shared/upload-utils.js';
import type { LoginBody, RegisterCaregiverBody, RegisterClientBody, PatchCaregiverProfileBody } from './auth.validation.js';
import type { JwtPayload } from '../../middleware/auth.middleware.js';
import logger from '../../shared/logger.js';
import { track, identify } from '../../shared/analytics.js';
import { blockchainService } from '../../services/blockchain.service.js';
import { getBoolSetting, getStringSetting } from '../../utils/settings-cache.js';

const SALT_ROUNDS = 12;

/** El enum `zone` de Prisma solo cubre las zonas de Santa Cruz — otras
 * ciudades (Cochabamba, etc.) usan keys propios que romperían la escritura
 * a esta columna. Descarta silenciosamente cualquier valor que no sea un
 * miembro real del enum, en vez de dejar que Prisma tire un 500. */
function safeZoneEnum(value: unknown): Zone | undefined {
  return typeof value === 'string' && (Object.values(Zone) as string[]).includes(value)
    ? (value as Zone)
    : undefined;
}

/** Edad en años cumplidos a partir de una fecha de nacimiento. */
export function calculateAge(dateOfBirth: Date): number {
  const today = new Date();
  let age = today.getFullYear() - dateOfBirth.getFullYear();
  const m = today.getMonth() - dateOfBirth.getMonth();
  if (m < 0 || (m === 0 && today.getDate() < dateOfBirth.getDate())) age--;
  return age;
}

export interface AuthTokens {
  accessToken: string;
  refreshToken: string;
  expiresIn: string;
  user: { id: string; email: string; role: string; activeRole?: string | null; firstName: string; lastName: string; profilePicture?: string | null };
}

export interface RegisterCaregiverResult {
  user: { id: string; email: string; role: string; firstName: string; lastName: string; profilePicture?: string | null };
  profileId: string;
  verificationStatus: VerificationStatus;
  accessToken: string;
  refreshToken: string;
  expiresIn: string;
}

export interface RegisterClientResult {
  user: { id: string; email: string; role: string; firstName: string; lastName: string; profilePicture?: string | null };
  profileId: string;
  accessToken: string;
  refreshToken: string;
  expiresIn: string;
}

/** Hash de contraseña con bcrypt */
export async function hashPassword(password: string): Promise<string> {
  return bcrypt.hash(password, SALT_ROUNDS);
}

/** Comparar contraseña con hash */
export async function comparePassword(password: string, hash: string): Promise<boolean> {
  return bcrypt.compare(password, hash);
}

/** Generar JWT de acceso */
export function signAccessToken(payload: JwtPayload): { token: string; expiresIn: string } {
  const expiresIn = env.JWT_EXPIRES_IN;
  // Omitir activeRole del token si coincide con el rol permanente (evita payload innecesario)
  const tokenPayload: JwtPayload = { ...payload };
  if (tokenPayload.activeRole === tokenPayload.role) delete tokenPayload.activeRole;
  const token = jwt.sign(tokenPayload, env.JWT_SECRET, { expiresIn } as jwt.SignOptions);
  return { token, expiresIn };
}

const REFRESH_TOKEN_EXPIRY_DAYS = 30;

/**
 * Genera un refresh token opaco (64 bytes hex), lo almacena hasheado (SHA-256),
 * y devuelve el token en claro para enviarlo al cliente.
 */
export async function createRefreshToken(userId: string): Promise<string> {
  const raw = randomBytes(64).toString('hex');
  const tokenHash = createHash('sha256').update(raw).digest('hex');
  const expiresAt = new Date(Date.now() + REFRESH_TOKEN_EXPIRY_DAYS * 24 * 60 * 60 * 1000);
  await prisma.refreshToken.create({ data: { userId, tokenHash, expiresAt } });
  return raw;
}

/**
 * Rota el refresh token:
 *   1. Busca el token por hash
 *   2. Verifica que no esté revocado ni expirado
 *   3. Revoca el token actual
 *   4. Emite un nuevo access token + nuevo refresh token
 * Devuelve null si el token es inválido, expirado o ya fue usado.
 */
export async function rotateRefreshToken(
  rawToken: string
): Promise<{ accessToken: string; refreshToken: string; expiresIn: string } | null> {
  const tokenHash = createHash('sha256').update(rawToken).digest('hex');
  const stored = await prisma.refreshToken.findUnique({ where: { tokenHash } });

  if (!stored || stored.revokedAt !== null || stored.expiresAt < new Date()) {
    return null;
  }

  // Revocar el token usado (evita reuso — token rotation)
  await prisma.refreshToken.update({ where: { id: stored.id }, data: { revokedAt: new Date() } });

  const user = await prisma.user.findUnique({
    where: { id: stored.userId },
    select: { id: true, role: true, activeRole: true, isDeleted: true },
  });
  if (!user || user.isDeleted) return null;

  const payload: JwtPayload = { userId: user.id, role: user.role };
  if (user.activeRole) payload.activeRole = user.activeRole;
  const { token: accessToken, expiresIn } = signAccessToken(payload);
  const newRefreshToken = await createRefreshToken(user.id);

  return { accessToken, refreshToken: newRefreshToken, expiresIn };
}

/**
 * Revoca todos los refresh tokens activos de un usuario.
 * Usar en logout para invalidar todas las sesiones.
 */
export async function revokeAllRefreshTokens(userId: string): Promise<void> {
  await prisma.refreshToken.updateMany({
    where: { userId, revokedAt: null },
    data: { revokedAt: new Date() },
  });
}

/**
 * Registro cuidador (full submit).
 * Transacción: crear User (role CAREGIVER) + CaregiverProfile (verificationStatus PENDING_REVIEW).
 * Valida uniques: email y phone. 409 si ya existen.
 */
/**
 * Beta-access guard — shared by both register flows.
 *
 * When `betaInviteRequired` AppSetting is true the caller must supply an
 * `inviteCode` that matches one of the codes stored in `betaInviteCodes`
 * (JSON array of strings).  If the code is missing or invalid a
 * `BadRequestError` with code `INVALID_INVITE_CODE` is thrown.
 *
 * When `betaInviteRequired` is false (the default) the function is a no-op.
 */
export async function assertBetaAccess(inviteCode?: string): Promise<void> {
  const required = await getBoolSetting('betaInviteRequired', false);
  if (!required) return;

  const raw = await getStringSetting('betaInviteCodes', '[]');
  let codes: string[] = [];
  try { codes = JSON.parse(raw) as string[]; } catch { codes = []; }

  const submitted = (inviteCode ?? '').trim();
  if (!submitted || !codes.includes(submitted)) {
    throw new BadRequestError(
      'Código de invitación inválido o no proporcionado. GARDEN está en beta cerrada.',
      'INVALID_INVITE_CODE'
    );
  }
}

/**
 * Rechaza el registro/edición si la zona elegida fue deshabilitada por un
 * admin (AppSettings.blockedZones). Sin esto, un cuidador podía registrarse
 * o cambiar su zona a una que el mapa y los filtros ya no muestran —
 * quedando "invisible" para los clientes sin que él lo supiera.
 */
async function assertZoneNotBlocked(zone: string | null | undefined): Promise<void> {
  if (!zone) return;
  const { isZoneBlocked } = await import('../admin/admin.service.js');
  if (await isZoneBlocked(zone)) {
    throw new BadRequestError(
      'Esta zona no está disponible temporalmente. Elige otra zona para continuar.',
      'ZONE_BLOCKED',
      'zone'
    );
  }
}

export async function registerCaregiver(body: RegisterCaregiverBody): Promise<RegisterCaregiverResult> {
  const { user: userInput, profile: profileInput } = body;

  // Beta access gate — no-op when betaInviteRequired=false
  await assertBetaAccess(body.inviteCode);
  await assertZoneNotBlocked(profileInput.zone);

  const [existingEmail, existingPhone] = await Promise.all([
    prisma.user.findUnique({ where: { email: userInput.email.toLowerCase() } }),
    prisma.user.findUnique({ where: { phone: userInput.phone } }),
  ]);

  if (existingEmail) {
    logger.warn('Intento de registro duplicado - email', {
      email: userInput.email.toLowerCase(),
      phone: userInput.phone,
    });
    throw new ConflictError('Ya existe una cuenta con este email', 'EMAIL_EXISTS', 'email');
  }
  if (existingPhone) {
    logger.warn('Intento de registro duplicado - teléfono', {
      email: userInput.email.toLowerCase(),
      phone: userInput.phone,
    });
    throw new ConflictError('Ya existe una cuenta con este teléfono', 'PHONE_EXISTS', 'phone');
  }

  const passwordHash = await hashPassword(userInput.password);
  const email = userInput.email.toLowerCase().trim();

  const dateOfBirth = userInput.dateOfBirth instanceof Date
    ? userInput.dateOfBirth
    : userInput.dateOfBirth
      ? new Date(userInput.dateOfBirth as string)
      : undefined;

  const profileAddr = profileInput as {
    addressLat?: number; addressLng?: number;
    addressStreet?: string; addressNumber?: string; addressApartment?: string;
    addressCondominio?: string; addressReference?: string; addressZone?: string;
    cityId?: string; zoneId?: string;
  };

  let result: { user: Awaited<ReturnType<typeof prisma.user.create>>; profile: Awaited<ReturnType<typeof prisma.caregiverProfile.create>> };
  try {
    result = await prisma.$transaction(async (tx) => {
      const user = await tx.user.create({
        data: {
          email,
          passwordHash,
          role: UserRole.CAREGIVER,
          firstName: userInput.firstName.trim(),
          lastName: userInput.lastName.trim(),
          phone: userInput.phone.trim(),
          dateOfBirth: dateOfBirth ?? undefined,
          country: userInput.country.trim(),
          city: userInput.city.trim(),
          isOver18: userInput.isOver18 === true,
        },
      });

      const profile = await tx.caregiverProfile.create({
        data: {
          userId: user.id,
          bio: profileInput.bio ?? null,
          zone: profileInput.zone ?? null,
          spaceType: Array.isArray(profileInput.spaceType) ? profileInput.spaceType : (profileInput.spaceType ? [profileInput.spaceType] : []),
          address: profileInput.address ?? null,
          ...(profileAddr.addressLat != null ? { addressLat: profileAddr.addressLat } : {}),
          ...(profileAddr.addressLng != null ? { addressLng: profileAddr.addressLng } : {}),
          ...(profileAddr.addressStreet ? { addressStreet: profileAddr.addressStreet } : {}),
          ...(profileAddr.addressNumber ? { addressNumber: profileAddr.addressNumber } : {}),
          ...(profileAddr.addressApartment ? { addressApartment: profileAddr.addressApartment } : {}),
          ...(profileAddr.addressCondominio ? { addressCondominio: profileAddr.addressCondominio } : {}),
          ...(profileAddr.addressReference ? { addressReference: profileAddr.addressReference } : {}),
          ...(profileAddr.addressZone ? { addressZone: profileAddr.addressZone } : {}),
          ...(profileAddr.cityId ? { cityId: profileAddr.cityId } : {}),
          ...(profileAddr.zoneId ? { zoneId: profileAddr.zoneId } : {}),
          photos: ensureAbsoluteUrls(profileInput.photos ?? []),
          walkerPhotos: [],
          servicesOffered: profileInput.servicesOffered ?? [],
          serviceAvailability: (profileInput.serviceAvailability ?? null) as object,
          pricePerDay: profileInput.pricePerDay ?? null,
          pricePerWalk30: profileInput.pricePerWalk30 ?? null,
          pricePerWalk60: profileInput.pricePerWalk60 ?? null,
          rates: (profileInput.rates ?? null) as object,
          status: CaregiverStatus.DRAFT,
          verificationStatus: VerificationStatus.PENDING_REVIEW,
          onboardingStatus: { step: 1, completed: [false, false, false, false, false] } as object,
          identityVerificationStatus: 'PENDING',
          identityVerificationToken: randomBytes(32).toString('hex'),
          emailVerified: false,
          verified: false,
          experienceYears: profileInput.experienceYears ?? null,
          // isAmateur=true cuando el cuidador declara 0 años de experiencia al registrarse
          isAmateur: (profileInput.experienceYears ?? -1) === 0,
          ownPets: profileInput.ownPets ?? null,
          currentPetsDetails: (profileInput.currentPetsDetails ?? null) as object,
          caredOthers: profileInput.caredOthers ?? null,
          animalTypes: profileInput.animalTypes ?? [],
          experienceDescription: profileInput.experienceDescription ?? null,
          whyCaregiver: profileInput.whyCaregiver ?? null,
          whatDiffers: profileInput.whatDiffers ?? null,
          handleAnxious: profileInput.handleAnxious ?? null,
          emergencyResponse: profileInput.emergencyResponse ?? null,
          acceptAggressive: profileInput.acceptAggressive ?? null,
          acceptMedication: profileInput.acceptMedication ?? [],
          acceptPuppies: profileInput.acceptPuppies ?? null,
          acceptSeniors: profileInput.acceptSeniors ?? null,
          sizesAccepted: profileInput.sizesAccepted ?? [],
          noAcceptBreeds: profileInput.noAcceptBreeds ?? null,
          breedsWhy: profileInput.breedsWhy ?? null,
          homeType: profileInput.homeType ?? null,
          ownHome: profileInput.ownHome ?? null,
          hasYard: profileInput.hasYard ?? null,
          yardFenced: profileInput.yardFenced ?? null,
          hasChildren: profileInput.hasChildren ?? null,
          hasOtherPets: profileInput.hasOtherPets ?? null,
          petsSleep: profileInput.petsSleep ?? null,
          clientPetsSleep: profileInput.clientPetsSleep ?? null,
          hoursAlone: profileInput.hoursAlone ?? null,
          workFromHome: profileInput.workFromHome ?? null,
          maxPets: profileInput.maxPets ?? null,
          oftenOut: profileInput.oftenOut ?? null,
          typicalDay: profileInput.typicalDay ?? null,
          profilePhoto: ensureAbsoluteUrl(profileInput.profilePhoto) ?? null,
          ciAnversoUrl: ensureAbsoluteUrl(profileInput.ciAnversoUrl) ?? null,
          ciReversoUrl: ensureAbsoluteUrl(profileInput.ciReversoUrl) ?? null,
          ciNumber: profileInput.ciNumber ?? null,
          defaultAvailabilitySchedule: {
            hospedajeDefault: true,
            paseoTimeBlocks: {
              morning: { enabled: true, start: '08:00', end: '11:00' },
              afternoon: { enabled: true, start: '13:00', end: '17:00' },
              night: { enabled: true, start: '19:00', end: '22:00' }
            }
          },
        },
      });

      return { user, profile };
    });
  } catch (error: unknown) {
    const err = error as { code?: string; meta?: { target?: unknown }; message?: string; stack?: string };
    logger.error('Fallo al crear User+CaregiverProfile (transacción revocada automáticamente)', {
      code: err.code,
      meta: err.meta,
      message: err.message,
      stack: err.stack,
      input: { email: userInput.email, phone: userInput.phone, firstName: userInput.firstName, lastName: userInput.lastName },
    });
    if (err.code === 'P2002') {
      const target = Array.isArray(err.meta?.target) ? (err.meta!.target as string[]) : [];
      if (target.includes('email')) throw new ConflictError('El email ya está registrado', 'EMAIL_EXISTS', 'email');
      if (target.includes('phone')) throw new ConflictError('El teléfono ya está registrado', 'PHONE_EXISTS', 'phone');
      throw new ConflictError('El email o teléfono ya está registrado', 'UNIQUE_VIOLATION');
    }
    throw error;
  }

  // Sincronizar Caregiver en Blockchain (asíncrono)
  blockchainService.syncProfileOnChain(
    result.user.id,
    `${result.user.firstName} ${result.user.lastName}`,
    'CAREGIVER',
    false // Empieza no verificado hasta que admin/proceso apruebe
  ).catch(err => logger.error('Blockchain sync failed (caregiver register)', { userId: result.user.id, err }));

  const savedPhotos = ensureAbsoluteUrls(profileInput.photos ?? []);
  if (savedPhotos.length > 0) {
    logger.info('Foto subida y guardada', {
      url: savedPhotos[0],
      field: 'photos',
      userId: result.user.id,
      count: savedPhotos.length,
    });
  }
  const ciAnverso = ensureAbsoluteUrl(profileInput.ciAnversoUrl);
  const ciReverso = ensureAbsoluteUrl(profileInput.ciReversoUrl);
  if (ciAnverso) {
    logger.info('Foto subida y guardada', { url: ciAnverso, field: 'ciAnversoUrl', userId: result.user.id });
  }
  if (ciReverso) {
    logger.info('Foto subida y guardada', { url: ciReverso, field: 'ciReversoUrl', userId: result.user.id });
  }

  const payload: JwtPayload = {
    userId: result.user.id,
    role: result.user.role,
  };
  const { token: accessToken, expiresIn } = signAccessToken(payload);
  const refreshToken = await createRefreshToken(result.user.id);

  // Analytics: caregiver registered
  track(result.user.id, 'user_registered', { role: 'CAREGIVER', email: result.user.email });
  identify(result.user.id, { role: 'CAREGIVER', email: result.user.email, firstName: result.user.firstName, lastName: result.user.lastName });

  return {
    user: {
      id: result.user.id,
      email: result.user.email,
      role: result.user.role,
      firstName: result.user.firstName,
      lastName: result.user.lastName,
      profilePicture: result.user.profilePicture,
    },
    profileId: result.profile.id,
    verificationStatus: result.profile.verificationStatus,
    accessToken,
    refreshToken,
    expiresIn,
  };
}

/**
 * Registro cliente (dueño de mascota).
 * Crear User (role CLIENT) + ClientProfile vacío (isComplete = false).
 * Valida uniques: email y phone. 409 si ya existen.
 * Logging exhaustivo en cada paso para diagnosticar 500.
 */
export async function registerClient(body: RegisterClientBody): Promise<RegisterClientResult> {
  if (!prisma) {
    logger.error('Prisma Client no inicializado');
    throw new Error('Database client not available');
  }
  if (typeof prisma.user?.create !== 'function') {
    logger.error('Prisma Client sin modelo user; ejecuta npx prisma generate');
    throw new Error('Database client not available');
  }
  // Beta access gate — no-op when betaInviteRequired=false
  await assertBetaAccess(body.inviteCode);

  logger.info('Inicio registro cliente', {
    input: {
      firstName: body.firstName,
      lastName: body.lastName,
      email: body.email,
      phone: body.phone,
      hasAddress: body.address != null && body.address !== '',
      passwordLength: typeof body.password === 'string' ? body.password.length : 0,
    },
  });

  const [existingEmail, existingPhone] = await Promise.all([
    prisma.user.findUnique({ where: { email: body.email.toLowerCase() } }),
    prisma.user.findUnique({ where: { phone: body.phone } }),
  ]);

  if (existingEmail) {
    logger.warn('Intento de registro cliente duplicado - email', {
      email: body.email.toLowerCase(),
      phone: body.phone,
    });
    throw new ConflictError('Ya existe una cuenta con este email', 'EMAIL_EXISTS', 'email');
  }
  if (existingPhone) {
    logger.warn('Intento de registro cliente duplicado - teléfono', {
      email: body.email.toLowerCase(),
      phone: body.phone,
    });
    throw new ConflictError('Ya existe una cuenta con este teléfono', 'PHONE_EXISTS', 'phone');
  }

  const rawPassword = body.password;
  if (typeof rawPassword !== 'string' || rawPassword.length < 8) {
    throw new BadRequestError('Contraseña inválida o demasiado corta', 'INVALID_PASSWORD');
  }
  let passwordHash: string;
  try {
    logger.info('Iniciando hash de contraseña');
    passwordHash = await hashPassword(rawPassword);
    logger.info('Hash completado');
  } catch (hashErr) {
    logger.error('Error al hashear contraseña en registro cliente', {
      error: hashErr instanceof Error ? hashErr.message : String(hashErr),
      stack: hashErr instanceof Error ? hashErr.stack : undefined,
    });
    throw new BadRequestError('Error al procesar la contraseña', 'PASSWORD_HASH_ERROR');
  }

  const email = body.email.toLowerCase().trim();

  const bodyExt = body as { dateOfBirth?: Date; bio?: string };
  const userData = {
    email,
    passwordHash,
    role: UserRole.CLIENT,
    firstName: body.firstName,
    lastName: body.lastName,
    phone: body.phone.trim(),
    country: 'Bolivia',
    city: 'Santa Cruz',
    isOver18: true,
    ...(bodyExt.dateOfBirth ? { dateOfBirth: bodyExt.dateOfBirth } : {}),
  };
  logger.info('Creando User+ClientProfile en transacción', { email: userData.email, phone: userData.phone });

  let user: { id: string; email: string; role: string; firstName: string; lastName: string; profilePicture?: string | null };
  let profile: { id: string };

  try {
    const result = await prisma.$transaction(async (tx) => {
      const created = await tx.user.create({ data: userData });
      logger.info('User creado (tx)', { id: created.id, email: created.email });
      const bodyAddr = body as {
        addressLat?: number; addressLng?: number;
        addressStreet?: string; addressNumber?: string; addressApartment?: string;
        addressCondominio?: string; addressReference?: string; addressZone?: string;
        cityId?: string; zoneId?: string;
      };
      const prof = await tx.clientProfile.create({
        data: {
          userId: created.id,
          address: body.address != null && typeof body.address === 'string' && body.address.trim() !== ''
            ? body.address.trim()
            : null,
          phone: body.phone.trim(),
          isComplete: false,
          ...(bodyExt.bio ? { bio: bodyExt.bio } : {}),
          ...(bodyAddr.addressLat != null ? { addressLat: bodyAddr.addressLat } : {}),
          ...(bodyAddr.addressLng != null ? { addressLng: bodyAddr.addressLng } : {}),
          ...(bodyAddr.addressStreet ? { addressStreet: bodyAddr.addressStreet } : {}),
          ...(bodyAddr.addressNumber ? { addressNumber: bodyAddr.addressNumber } : {}),
          ...(bodyAddr.addressApartment ? { addressApartment: bodyAddr.addressApartment } : {}),
          ...(bodyAddr.addressCondominio ? { addressCondominio: bodyAddr.addressCondominio } : {}),
          ...(bodyAddr.addressReference ? { addressReference: bodyAddr.addressReference } : {}),
          ...(bodyAddr.addressZone ? { addressZone: bodyAddr.addressZone } : {}),
          ...(bodyAddr.cityId ? { cityId: bodyAddr.cityId } : {}),
          ...(bodyAddr.zoneId ? { zoneId: bodyAddr.zoneId } : {}),
        },
      });
      logger.info('ClientProfile creado (tx)', { id: prof.id });
      return { user: created, profile: prof };
    });

    user = {
      id: result.user.id,
      email: result.user.email,
      role: result.user.role,
      firstName: result.user.firstName,
      lastName: result.user.lastName,
      profilePicture: result.user.profilePicture,
    };
    profile = { id: result.profile.id };
  } catch (error: unknown) {
    const err = error as { code?: string; meta?: { target?: unknown }; message?: string; stack?: string };
    logger.error('Fallo al crear User+ClientProfile (transacción revocada automáticamente)', {
      code: err.code,
      meta: err.meta,
      message: err.message,
      stack: err.stack,
      input: { email: body.email, phone: body.phone, firstName: body.firstName, lastName: body.lastName },
    });
    if (err.code === 'P2002') {
      const target = Array.isArray(err.meta?.target) ? (err.meta.target as string[]) : [];
      if (target.includes('email')) {
        throw new ConflictError('El email ya está registrado', 'EMAIL_EXISTS', 'email');
      }
      if (target.includes('phone')) {
        throw new ConflictError('El teléfono ya está registrado', 'PHONE_EXISTS', 'phone');
      }
      throw new ConflictError('El email o teléfono ya está registrado', 'UNIQUE_VIOLATION');
    }
    throw error;
  }

  // Sincronizar Cliente en Blockchain (asíncrono)
  blockchainService.syncProfileOnChain(
    user.id,
    `${user.firstName} ${user.lastName}`,
    'CLIENT',
    false
  ).catch(err => logger.error('Blockchain sync failed (client register)', { userId: user.id, err }));

  const payload: JwtPayload = { userId: user.id, role: user.role };
  const { token, expiresIn } = signAccessToken(payload);
  const refreshToken = await createRefreshToken(user.id);
  logger.info('Cliente registrado exitosamente', { userId: user.id, email: user.email });
  // Analytics: client registered
  track(user.id, 'user_registered', { role: 'CLIENT', email: user.email });
  identify(user.id, { role: 'CLIENT', email: user.email, firstName: user.firstName, lastName: user.lastName });
  return {
    user,
    profileId: profile.id,
    accessToken: token,
    refreshToken,
    expiresIn,
  };
}

/**
 * Login: email + password. Devuelve JWT y datos de usuario.
 * Si roleFilter = 'CAREGIVER', rechaza con 400 si el usuario no es cuidador.
 */
export async function login(
  body: LoginBody,
  roleFilter?: 'CAREGIVER'
): Promise<AuthTokens> {
  const email = body.email.toLowerCase().trim();
  logger.info('Login attempt', { email, roleFilter: roleFilter ?? 'any' });

  const user = await prisma.user.findUnique({
    where: { email },
  });

  // Check isDeleted BEFORE leaking "user not found" vs "account deleted" distinction
  if (!user || user.isDeleted) {
    logger.warn('Login: user not found or deleted', { email });
    throw new UnauthorizedError('Credenciales inválidas');
  }

  const valid = await comparePassword(body.password, user.passwordHash);
  logger.info('Login: password match', { email, match: valid });
  if (!valid) {
    throw new UnauthorizedError('Credenciales inválidas');
  }

  if (roleFilter === 'CAREGIVER' && user.role !== UserRole.CAREGIVER) {
    logger.warn('Login: role rejected (se requiere CAREGIVER)', { email, role: user.role });
    throw new BadRequestError('Esta ruta es solo para cuidadores', 'INVALID_ROLE');
  }

  const payload: JwtPayload = { userId: user.id, role: user.role };
  const { token: accessToken, expiresIn } = signAccessToken(payload);
  const refreshToken = await createRefreshToken(user.id);

  return {
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
  };
}

/**
 * Actualizar perfil del cuidador (solo campos enviados).
 * Solo el propio usuario puede actualizar. verificationStatus no se cambia por aquí.
 */
export async function updateCaregiverProfile(
  userId: string,
  body: PatchCaregiverProfileBody
): Promise<{ profileId: string }> {
  const profile = await prisma.caregiverProfile.findUnique({ where: { userId } });
  if (!profile) {
    throw new BadRequestError('No tienes perfil de cuidador', 'CAREGIVER_PROFILE_NOT_FOUND');
  }
  if (body.zone !== undefined) await assertZoneNotBlocked(body.zone);

  const updateData: Record<string, unknown> = {};
  if (body.bio !== undefined) updateData.bio = body.bio;
  if (body.zone !== undefined) updateData.zone = body.zone;
  if (body.spaceType !== undefined) {
    updateData.spaceType = Array.isArray(body.spaceType) ? body.spaceType : (body.spaceType ? [body.spaceType] : []);
  }
  if (body.address !== undefined) updateData.address = body.address;
  if (body.servicesOffered !== undefined) updateData.servicesOffered = body.servicesOffered;
  if (body.serviceAvailability !== undefined) updateData.serviceAvailability = body.serviceAvailability;
  if (body.pricePerDay !== undefined) updateData.pricePerDay = body.pricePerDay;
  if (body.pricePerWalk30 !== undefined) updateData.pricePerWalk30 = body.pricePerWalk30;
  if (body.pricePerWalk60 !== undefined) updateData.pricePerWalk60 = body.pricePerWalk60;
  if (body.rates !== undefined) updateData.rates = body.rates;
  if (body.experienceYears !== undefined) {
    updateData.experienceYears = body.experienceYears;
    // Recalcular isAmateur dinámicamente:
    // - Si años == 0 → amateur (sin importar approvedAt)
    // - Si años >= 1 → ya no es amateur
    // La lógica de "1 año desde approvedAt → dejar de ser amateur" se resuelve
    // cuando el cuidador edita y coloca >= 1 año, o vía getProfile (ver abajo).
    updateData.isAmateur = body.experienceYears === 0;
  }
  if (body.ownPets !== undefined) updateData.ownPets = body.ownPets;
  if (body.currentPetsDetails !== undefined) updateData.currentPetsDetails = body.currentPetsDetails;
  if (body.caredOthers !== undefined) updateData.caredOthers = body.caredOthers;
  if (body.animalTypes !== undefined) updateData.animalTypes = body.animalTypes;
  if (body.experienceDescription !== undefined) updateData.experienceDescription = body.experienceDescription;
  if (body.whyCaregiver !== undefined) updateData.whyCaregiver = body.whyCaregiver;
  if (body.whatDiffers !== undefined) updateData.whatDiffers = body.whatDiffers;
  if (body.handleAnxious !== undefined) updateData.handleAnxious = body.handleAnxious;
  if (body.emergencyResponse !== undefined) updateData.emergencyResponse = body.emergencyResponse;
  if (body.acceptAggressive !== undefined) updateData.acceptAggressive = body.acceptAggressive;
  if (body.acceptMedication !== undefined) updateData.acceptMedication = body.acceptMedication;
  if (body.acceptPuppies !== undefined) updateData.acceptPuppies = body.acceptPuppies;
  if (body.acceptSeniors !== undefined) updateData.acceptSeniors = body.acceptSeniors;
  if (body.sizesAccepted !== undefined) updateData.sizesAccepted = body.sizesAccepted;
  if (body.noAcceptBreeds !== undefined) updateData.noAcceptBreeds = body.noAcceptBreeds;
  if (body.breedsWhy !== undefined) updateData.breedsWhy = body.breedsWhy;
  if (body.homeType !== undefined) updateData.homeType = body.homeType;
  if (body.ownHome !== undefined) updateData.ownHome = body.ownHome;
  if (body.hasYard !== undefined) updateData.hasYard = body.hasYard;
  if (body.yardFenced !== undefined) updateData.yardFenced = body.yardFenced;
  if (body.hasChildren !== undefined) updateData.hasChildren = body.hasChildren;
  if (body.hasOtherPets !== undefined) updateData.hasOtherPets = body.hasOtherPets;
  if (body.petsSleep !== undefined) updateData.petsSleep = body.petsSleep;
  if (body.clientPetsSleep !== undefined) updateData.clientPetsSleep = body.clientPetsSleep;
  if (body.hoursAlone !== undefined) updateData.hoursAlone = body.hoursAlone;
  if (body.workFromHome !== undefined) updateData.workFromHome = body.workFromHome;
  if (body.maxPets !== undefined) updateData.maxPets = body.maxPets;
  if (body.oftenOut !== undefined) updateData.oftenOut = body.oftenOut;
  if (body.typicalDay !== undefined) updateData.typicalDay = body.typicalDay;
  if (body.photos !== undefined) updateData.photos = ensureAbsoluteUrls(body.photos);
  const b = body as Record<string, unknown>;
  if (b.ciAnversoUrl !== undefined) updateData.ciAnversoUrl = ensureAbsoluteUrl(String(b.ciAnversoUrl)) ?? null;
  if (b.ciReversoUrl !== undefined) updateData.ciReversoUrl = ensureAbsoluteUrl(String(b.ciReversoUrl)) ?? null;
  if (b.ciNumber !== undefined) updateData.ciNumber = String(b.ciNumber);

  await prisma.caregiverProfile.update({
    where: { id: profile.id },
    data: updateData,
  });

  return { profileId: profile.id };
}


// ── Register Professional ─────────────────────────────────────────────────────

export interface RegisterProfessionalBody {
  code: string;
  email: string;
  password: string;
  firstName: string;
  lastName: string;
  phone: string;
  bio?: string;
  zone?: string;
  services?: string[];
  pricePerDay?: number;
  pricePerWalk60?: number;
  photos?: string[];
  profilePhoto?: string;
  address?: string;
  [key: string]: unknown;
}

/**
 * Verifica que el código de registro profesional es válido.
 * No crea nada — solo comprueba el código contra AppSettings.professionalRegistrationCode.
 */
export async function validateProfessionalCode(code: string): Promise<boolean> {
  const stored = await getStringSetting('professionalRegistrationCode', '');
  if (!stored || stored.trim() === '') return false;
  return code.trim() === stored.trim();
}

/**
 * Registro de cuidador profesional.
 * Requiere code == AppSettings.professionalRegistrationCode.
 * Crea usuario CAREGIVER + CaregiverProfile con isProfessional=true, verified=true, status=APPROVED.
 */
export async function registerProfessional(body: RegisterProfessionalBody): Promise<RegisterCaregiverResult> {
  // Validate code
  const valid = await validateProfessionalCode(body.code);
  if (!valid) {
    throw new BadRequestError(
      'Código de registro profesional inválido.',
      'INVALID_PROFESSIONAL_CODE'
    );
  }
  await assertZoneNotBlocked((body as any).zone);

  const [existingEmail, existingPhone] = await Promise.all([
    prisma.user.findUnique({ where: { email: body.email.toLowerCase() } }),
    prisma.user.findUnique({ where: { phone: body.phone } }),
  ]);

  if (existingEmail) throw new ConflictError('Ya existe una cuenta con este email', 'EMAIL_EXISTS', 'email');
  if (existingPhone) throw new ConflictError('Ya existe una cuenta con este teléfono', 'PHONE_EXISTS', 'phone');

  const passwordHash = await hashPassword(body.password);
  const email = body.email.toLowerCase().trim();

  const now = new Date();
  const cityId = (body as any).cityId as string | undefined;
  const zoneId = (body as any).zoneId as string | undefined;
  const cityRecord = cityId ? await prisma.city.findUnique({ where: { id: cityId } }) : null;

  const result = await prisma.$transaction(async (tx) => {
    const user = await tx.user.create({
      data: {
        email,
        passwordHash,
        role: UserRole.CAREGIVER,
        firstName: body.firstName.trim(),
        lastName: body.lastName.trim(),
        phone: body.phone.trim(),
        country: 'Bolivia',
        city: cityRecord?.name ?? 'Santa Cruz de la Sierra',
        isOver18: true,
      },
    });

    const profile = await tx.caregiverProfile.create({
      data: {
        userId: user.id,
        bio: typeof body.bio === 'string' ? body.bio : null,
        zone: safeZoneEnum(body.zone) ?? null,
        ...(cityId ? { cityId } : {}),
        ...(zoneId ? { zoneId } : {}),
        photos: ensureAbsoluteUrls((body.photos ?? []) as string[]),
        profilePhoto: ensureAbsoluteUrl(body.profilePhoto as string | undefined) ?? null,
        servicesOffered: (body.services ?? []) as any[],
        pricePerDay: body.pricePerDay ?? null,
        pricePerWalk60: body.pricePerWalk60 ?? null,
        address: typeof body.address === 'string' ? body.address : null,
        status: CaregiverStatus.APPROVED,
        verified: true,
        verifiedAt: now,
        approvedAt: now,
        identityVerificationStatus: 'VERIFIED',
        identityVerificationToken: randomBytes(32).toString('hex'),
        emailVerified: true,
        isProfessional: true,
        defaultAvailabilitySchedule: {
          hospedajeDefault: true,
          paseoTimeBlocks: {
            morning: { enabled: true, start: '08:00', end: '11:00' },
            afternoon: { enabled: true, start: '13:00', end: '17:00' },
            night: { enabled: true, start: '19:00', end: '22:00' }
          }
        },
      },
    });

    return { user, profile };
  });

  // Blockchain sync (async, non-blocking)
  blockchainService.syncProfileOnChain(
    result.user.id,
    `${result.user.firstName} ${result.user.lastName}`,
    'CAREGIVER',
    true // professional = verified from the start
  ).catch(err => logger.error('Blockchain sync failed (professional register)', { userId: result.user.id, err }));

  const payload: JwtPayload = { userId: result.user.id, role: result.user.role };
  const { token: accessToken, expiresIn } = signAccessToken(payload);
  const refreshToken = await createRefreshToken(result.user.id);

  track(result.user.id, 'user_registered', { role: 'CAREGIVER', professional: true, email: result.user.email });
  identify(result.user.id, { role: 'CAREGIVER', professional: true, email: result.user.email, firstName: result.user.firstName, lastName: result.user.lastName });

  return {
    user: {
      id: result.user.id,
      email: result.user.email,
      role: result.user.role,
      firstName: result.user.firstName,
      lastName: result.user.lastName,
      profilePicture: result.user.profilePicture,
    },
    profileId: result.profile.id,
    verificationStatus: result.profile.verificationStatus,
    accessToken,
    refreshToken,
    expiresIn,
  };
}

// ── Company Registration ──────────────────────────────────────────────────────

export async function validateCompanyCode(code: string): Promise<boolean> {
  const stored = await getStringSetting('companyRegistrationCode', '');
  if (!stored || stored.trim() === '') return false;
  return code.trim() === stored.trim();
}

export interface RegisterCompanyBody {
  code: string;
  companyName: string;
  businessType: string;
  email: string;
  password: string;
  phone: string;
  bio?: string;
  zone?: string;
  address?: string;
  lat?: number;
  lng?: number;
  services?: string[];
}

/**
 * Registro de empresa (hotel, hostal, guardería, etc.).
 * Requiere code == AppSettings.companyRegistrationCode.
 * Crea usuario CAREGIVER + CaregiverProfile con isCompany=true, isProfessional=true.
 * Status queda APPROVED; verified=false hasta completar phone+email verification.
 */
export async function registerCompany(body: RegisterCompanyBody): Promise<RegisterCaregiverResult> {
  const valid = await validateCompanyCode(body.code);
  if (!valid) {
    throw new BadRequestError('Código de registro de empresa inválido.', 'INVALID_COMPANY_CODE');
  }
  await assertZoneNotBlocked((body as any).zone);

  const [existingEmail, existingPhone] = await Promise.all([
    prisma.user.findUnique({ where: { email: body.email.toLowerCase() } }),
    prisma.user.findUnique({ where: { phone: body.phone } }),
  ]);
  if (existingEmail) throw new ConflictError('Ya existe una cuenta con este email', 'EMAIL_EXISTS', 'email');
  if (existingPhone) throw new ConflictError('Ya existe una cuenta con este teléfono', 'PHONE_EXISTS', 'phone');

  const passwordHash = await hashPassword(body.password);
  const email = body.email.toLowerCase().trim();
  const now = new Date();
  const cityId = (body as any).cityId as string | undefined;
  const zoneId = (body as any).zoneId as string | undefined;
  const cityRecord = cityId ? await prisma.city.findUnique({ where: { id: cityId } }) : null;

  const result = await prisma.$transaction(async (tx) => {
    const user = await tx.user.create({
      data: {
        email,
        passwordHash,
        role: UserRole.CAREGIVER,
        firstName: body.companyName.trim(),
        lastName: '-',
        phone: body.phone.trim(),
        country: 'Bolivia',
        city: cityRecord?.name ?? 'Santa Cruz de la Sierra',
        isOver18: true,
        emailVerified: false,
      },
    });

    const profile = await tx.caregiverProfile.create({
      data: {
        userId: user.id,
        bio: body.bio ?? null,
        zone: safeZoneEnum(body.zone) ?? null,
        ...(cityId ? { cityId } : {}),
        ...(zoneId ? { zoneId } : {}),
        address: body.address ?? null,
        servicesOffered: (body.services ?? []) as any[],
        status: CaregiverStatus.APPROVED,
        verified: false,            // set to true after phone+email verified
        verifiedAt: null,
        approvedAt: now,
        identityVerificationStatus: 'VERIFIED', // companies skip CI
        identityVerificationToken: randomBytes(32).toString('hex'),
        emailVerified: false,
        phoneVerified: false,
        isProfessional: true,
        isCompany: true,
        companyName: body.companyName.trim(),
        businessType: body.businessType.trim(),
        defaultAvailabilitySchedule: {
          hospedajeDefault: true,
          paseoTimeBlocks: {
            morning: { enabled: true, start: '08:00', end: '11:00' },
            afternoon: { enabled: true, start: '13:00', end: '17:00' },
            night: { enabled: true, start: '19:00', end: '22:00' },
          },
        },
      },
    });

    return { user, profile };
  });

  const payload: JwtPayload = { userId: result.user.id, role: result.user.role };
  const { token: accessToken, expiresIn } = signAccessToken(payload);
  const refreshToken = await createRefreshToken(result.user.id);

  track(result.user.id, 'user_registered', { role: 'CAREGIVER', company: true, email: result.user.email });

  return {
    user: {
      id: result.user.id,
      email: result.user.email,
      role: result.user.role,
      firstName: result.user.firstName,
      lastName: result.user.lastName,
      profilePicture: result.user.profilePicture,
    },
    profileId: result.profile.id,
    verificationStatus: result.profile.verificationStatus,
    accessToken,
    refreshToken,
    expiresIn,
  };
}

// ── Switch Role ───────────────────────────────────────────────────────────────

export interface SwitchRoleResult {
  accessToken: string;
  refreshToken: string;
  expiresIn: string;
  activeRole: string;
}

/**
 * Cambia el rol activo en sesión sin modificar el rol permanente del usuario.
 *
 * Reglas:
 *  - Un CAREGIVER puede activar rol CLIENT (para usar la app como dueño de mascota).
 *  - Cualquier usuario puede volver a su rol permanente pasando targetRole === su role permanente.
 *  - Un CLIENT no puede activar rol CAREGIVER por este endpoint (debe completar onboarding).
 *
 * Persiste `activeRole` en BD para que rotateRefreshToken propague el estado.
 * Emite nuevos tokens (access + refresh) con el rol activo en el payload.
 */
export async function switchRole(userId: string, targetRole: UserRole): Promise<SwitchRoleResult> {
  const user = await prisma.user.findUnique({
    where: { id: userId },
    select: { id: true, role: true, isDeleted: true },
  });

  if (!user || user.isDeleted) {
    throw new UnauthorizedError('Usuario no encontrado');
  }

  // Si el targetRole coincide con el rol permanente, limpiar activeRole
  const isRestoringOwnRole = targetRole === user.role;

  // Un ADMIN no puede cambiar de rol
  if (user.role === UserRole.ADMIN) {
    throw new ForbiddenError('Los administradores no pueden cambiar de rol.', 'ADMIN_ROLE_SWITCH_FORBIDDEN');
  }

  // Solo se permite cambiar a CLIENT o CAREGIVER — nunca a ADMIN
  // (previene escalada de privilegios: un CAREGIVER/CLIENT podría setear activeRole=ADMIN)
  const allowedTargetRoles: UserRole[] = [UserRole.CLIENT, UserRole.CAREGIVER];
  if (!isRestoringOwnRole && !allowedTargetRoles.includes(targetRole)) {
    throw new ForbiddenError('Rol de destino no válido.', 'INVALID_TARGET_ROLE');
  }

  // Un CLIENT no puede activar rol CAREGIVER sin onboarding
  if (!isRestoringOwnRole && user.role === UserRole.CLIENT && targetRole === UserRole.CAREGIVER) {
    throw new ForbiddenError(
      'Debes completar el proceso de registro como cuidador primero.',
      'CAREGIVER_ONBOARDING_REQUIRED'
    );
  }

  const newActiveRole = isRestoringOwnRole ? null : targetRole;

  // Persistir en BD
  await prisma.user.update({
    where: { id: userId },
    data: { activeRole: newActiveRole },
  });

  // Revocar tokens anteriores para invalidar sesiones antiguas
  await revokeAllRefreshTokens(userId);

  const payload: JwtPayload = { userId: user.id, role: user.role };
  if (newActiveRole) payload.activeRole = newActiveRole;

  const { token: accessToken, expiresIn } = signAccessToken(payload);
  const newRefreshToken = await createRefreshToken(userId);

  const effectiveRole = newActiveRole ?? user.role;
  logger.info('auth.service: rol activo cambiado', { userId, permanentRole: user.role, activeRole: effectiveRole });

  return { accessToken, refreshToken: newRefreshToken, expiresIn, activeRole: effectiveRole };
}

// ── Init Caregiver Profile (CLIENT → CAREGIVER) ──────────────────────────────

/**
 * Crea un CaregiverProfile vacío para un usuario CLIENT existente y cambia
 * su rol permanente a CAREGIVER. Devuelve nuevos tokens con role=CAREGIVER.
 *
 * Reglas:
 *  - El usuario debe tener role=CLIENT.
 *  - No debe tener ya un CaregiverProfile.
 */
export async function initCaregiverProfile(userId: string): Promise<SwitchRoleResult> {
  const user = await prisma.user.findUnique({
    where: { id: userId },
    select: { id: true, role: true, isDeleted: true, dateOfBirth: true },
  });

  if (!user || user.isDeleted) throw new UnauthorizedError('Usuario no encontrado');

  if (user.role !== UserRole.CLIENT) {
    throw new ForbiddenError('Solo cuentas de dueño de mascota pueden iniciar el proceso de cuidador.', 'WRONG_ROLE');
  }

  // Edad mínima 18 — un menor de edad solo puede ser dueño de mascota, nunca cuidador.
  // dateOfBirth puede faltar (ej. cuentas creadas por login social): se trata igual
  // que "menor de edad" hasta que el usuario lo complete en Mi Perfil.
  if (!user.dateOfBirth) {
    throw new BadRequestError(
      'Completa tu fecha de nacimiento en Mi Perfil antes de convertirte en cuidador.',
      'MISSING_DATE_OF_BIRTH'
    );
  }
  if (calculateAge(user.dateOfBirth) < 18) {
    throw new ForbiddenError('Debes tener al menos 18 años para registrarte como cuidador.', 'UNDERAGE_CAREGIVER');
  }

  const existing = await prisma.caregiverProfile.findUnique({ where: { userId } });
  if (existing) {
    throw new ConflictError('Ya tienes un perfil de cuidador registrado.', 'CAREGIVER_PROFILE_EXISTS');
  }

  await prisma.$transaction([
    prisma.caregiverProfile.create({
      data: {
        userId,
        status: CaregiverStatus.DRAFT,
        verificationStatus: VerificationStatus.PENDING_REVIEW,
      },
    }),
    prisma.user.update({
      where: { id: userId },
      data: { role: UserRole.CAREGIVER, activeRole: null },
    }),
  ]);

  await revokeAllRefreshTokens(userId);

  const payload: JwtPayload = { userId, role: UserRole.CAREGIVER };
  const { token: accessToken, expiresIn } = signAccessToken(payload);
  const newRefreshToken = await createRefreshToken(userId);

  logger.info('auth.service: CLIENT → CAREGIVER profile initialized', { userId });

  return { accessToken, refreshToken: newRefreshToken, expiresIn, activeRole: UserRole.CAREGIVER };
}

// ── Abandon Caregiver Profile (CAREGIVER → CLIENT revert) ────────────────────

/**
 * Revierte la conversión CLIENT→CAREGIVER:
 *  - Elimina el CaregiverProfile si está en estado DRAFT (no aprobado).
 *  - Restaura user.role a CLIENT.
 *  - Devuelve nuevos tokens con role=CLIENT.
 *
 * Solo funciona si el perfil está en DRAFT (no se puede abandonar si ya está aprobado).
 */
export async function abandonCaregiverProfile(userId: string): Promise<SwitchRoleResult> {
  const user = await prisma.user.findUnique({
    where: { id: userId },
    select: { id: true, role: true, isDeleted: true },
  });

  if (!user || user.isDeleted) throw new UnauthorizedError('Usuario no encontrado');

  if (user.role !== UserRole.CAREGIVER) {
    throw new ForbiddenError('Solo cuentas de cuidador pueden abandonar el proceso.', 'WRONG_ROLE');
  }

  const profile = await prisma.caregiverProfile.findUnique({ where: { userId } });
  if (!profile) {
    // No profile — just revert role
    await prisma.user.update({ where: { id: userId }, data: { role: UserRole.CLIENT, activeRole: null } });
  } else {
    // Allow abandonment from DRAFT, REJECTED, or NEEDS_REVISION.
    // PENDING_REVIEW, APPROVED, SUSPENDED require admin intervention.
    const abandonableStatuses: CaregiverStatus[] = [CaregiverStatus.DRAFT, CaregiverStatus.REJECTED, CaregiverStatus.NEEDS_REVISION];
    if (!abandonableStatuses.includes(profile.status)) {
      throw new ForbiddenError(
        'No puedes abandonar el proceso en el estado actual del perfil. Contacta al soporte si necesitas ayuda.',
        'PROFILE_NOT_ABANDONABLE'
      );
    }
    await prisma.$transaction([
      prisma.caregiverProfile.delete({ where: { userId } }),
      prisma.user.update({ where: { id: userId }, data: { role: UserRole.CLIENT, activeRole: null } }),
    ]);
  }

  await revokeAllRefreshTokens(userId);

  const payload: JwtPayload = { userId, role: UserRole.CLIENT };
  const { token: accessToken, expiresIn } = signAccessToken(payload);
  const newRefreshToken = await createRefreshToken(userId);

  logger.info('auth.service: CAREGIVER conversion abandoned → CLIENT', { userId });

  return { accessToken, refreshToken: newRefreshToken, expiresIn, activeRole: UserRole.CLIENT };
}
