/**
 * Teléfono de contacto: verificación, bloqueo y cambio autorizado.
 *
 * Reglas (el número es el canal de contacto entre dueño y cuidador, no puede
 * quedar en un valor que nadie confirmó):
 *  1. Mientras el número NO esté verificado se puede corregir libremente.
 *  2. Una vez verificado queda bloqueado: ningún endpoint de edición lo toca.
 *  3. Solo se puede cambiar dentro de una ventana que abre el bot de soporte
 *     (authorizePhoneChange), nunca el usuario por su cuenta.
 *  4. El número nuevo NO reemplaza a User.phone hasta que el código OTP llegue
 *     a ESE número y se confirme (commitPhoneChange). Si no se verifica, el
 *     número anterior sigue siendo el oficial — no hay estado intermedio con
 *     un número sin verificar.
 *
 * "Verificado" vive en CaregiverProfile.phoneVerified / ClientProfile.phoneVerified
 * (ya existían y la app los lee); como User.phone es uno solo, se considera
 * verificado si CUALQUIERA de los dos perfiles lo marca.
 */
import { Prisma } from '@prisma/client';
import prisma from '../../config/database.js';
import logger from '../../shared/logger.js';
import { BadRequestError, ConflictError, ForbiddenError } from '../../shared/errors.js';

export const PHONE_CHANGE_WINDOW_MINUTES = 30;
/** Tope de autorizaciones por usuario en 24h — frena el abuso del bot. */
const MAX_AUTHORIZATIONS_PER_DAY = 2;
const BO_PHONE = /^[67][0-9]{7}$/;

/** Devuelve el celular boliviano de 8 dígitos sin prefijo, o null si no es válido. */
export function normalizeBoPhone(raw: string): string | null {
  const clean = raw.trim().replace(/\D/g, '').replace(/^591/, '');
  return BO_PHONE.test(clean) ? clean : null;
}

export async function isPhoneVerified(userId: string): Promise<boolean> {
  const [caregiver, client] = await Promise.all([
    prisma.caregiverProfile.findUnique({ where: { userId }, select: { phoneVerified: true } }),
    prisma.clientProfile.findUnique({ where: { userId }, select: { phoneVerified: true } }),
  ]);
  return caregiver?.phoneVerified === true || client?.phoneVerified === true;
}

export interface PhoneState {
  phone: string | null;
  verified: boolean;
  pendingPhone: string | null;
  authorizedUntil: Date | null;
  /** true = verificado y con ventana de cambio abierta. */
  canChange: boolean;
}

/** Estado actual del teléfono. Limpia (lazy) una ventana vencida y su cambio pendiente. */
export async function getPhoneState(userId: string): Promise<PhoneState> {
  const user = await prisma.user.findUnique({
    where: { id: userId },
    select: { phone: true, pendingPhone: true, phoneChangeAuthorizedUntil: true },
  });
  const verified = await isPhoneVerified(userId);
  let pendingPhone = user?.pendingPhone ?? null;
  let authorizedUntil = user?.phoneChangeAuthorizedUntil ?? null;

  const expired = authorizedUntil !== null && authorizedUntil <= new Date();
  if (expired || (pendingPhone && !authorizedUntil)) {
    await prisma.user.updateMany({
      where: { id: userId },
      data: { pendingPhone: null, phoneChangeAuthorizedUntil: null, ...(pendingPhone ? { phoneOtp: null, phoneOtpExpiresAt: null } : {}) },
    });
    pendingPhone = null;
    authorizedUntil = null;
  }

  return {
    phone: user?.phone ?? null,
    verified,
    pendingPhone,
    authorizedUntil,
    canChange: verified && authorizedUntil !== null,
  };
}

/** Forma que se expone a la app (sin tocar el resto del estado interno). */
export function toPublicPhoneState(state: PhoneState) {
  return {
    phone: state.phone,
    verified: state.verified,
    pendingPhone: state.pendingPhone,
    canChange: state.canChange,
    changeAuthorizedUntil: state.authorizedUntil ? state.authorizedUntil.toISOString() : null,
  };
}

/**
 * Guarda para cualquier endpoint que edite User.phone directamente: si el
 * número verificado cambiaría, se rechaza. Si es el mismo número (la app
 * reenvía el campo en cada guardado) o aún no está verificado, deja pasar.
 */
export async function assertPhoneEditable(userId: string, newCleanPhone: string): Promise<void> {
  const state = await getPhoneState(userId);
  if (newCleanPhone === state.phone) return;
  if (state.verified) {
    throw new ForbiddenError(
      'Tu teléfono ya está verificado y no se puede editar. Si necesitas cambiarlo, solicítalo por el chat de soporte.',
      'PHONE_LOCKED'
    );
  }
}

export type AuthorizeResult =
  | { status: 'AUTHORIZED' | 'ALREADY_AUTHORIZED'; until: Date }
  | { status: 'NOT_VERIFIED' | 'RATE_LIMITED' };

/**
 * Abre la ventana de cambio. Solo la llama el chat de soporte (ver
 * support-chat.service.ts) — no hay ningún endpoint que la exponga al usuario.
 */
export async function authorizePhoneChange(userId: string): Promise<AuthorizeResult> {
  const state = await getPhoneState(userId);
  if (!state.verified) return { status: 'NOT_VERIFIED' };
  if (state.canChange && state.authorizedUntil) return { status: 'ALREADY_AUTHORIZED', until: state.authorizedUntil };

  const since = new Date(Date.now() - 24 * 60 * 60 * 1000);
  const recent = await prisma.adminNotification.count({
    where: { type: 'PHONE_CHANGE_AUTHORIZED', caregiverId: userId, createdAt: { gte: since } },
  });
  if (recent >= MAX_AUTHORIZATIONS_PER_DAY) return { status: 'RATE_LIMITED' };

  const until = new Date(Date.now() + PHONE_CHANGE_WINDOW_MINUTES * 60 * 1000);
  await prisma.user.update({
    where: { id: userId },
    data: { phoneChangeAuthorizedUntil: until, pendingPhone: null, phoneOtp: null, phoneOtpExpiresAt: null },
  });
  // Registro de auditoría (readAt ya seteado: no es una alerta pendiente para
  // el panel de admin, solo deja constancia de quién abrió una ventana y cuándo).
  await prisma.adminNotification.create({
    data: { type: 'PHONE_CHANGE_AUTHORIZED', caregiverId: userId, readAt: new Date() },
  });
  logger.info('[PhoneChange] Ventana de cambio de teléfono abierta por soporte', { userId, until: until.toISOString() });

  // Aviso al correo registrado: si alguien con la sesión robada pide el cambio,
  // el dueño real se entera. Best-effort — no bloquea la autorización.
  try {
    const user = await prisma.user.findUnique({ where: { id: userId }, select: { email: true, firstName: true } });
    if (user?.email && !user.email.endsWith('.deleted')) {
      const { sendTransactionalEmail } = await import('./email.service.js');
      await sendTransactionalEmail(
        user.email,
        'GARDEN – Se autorizó el cambio de tu teléfono',
        `<p>Hola ${user.firstName ?? ''},</p>` +
          `<p>Recibimos por el chat de soporte una solicitud para cambiar el teléfono de tu cuenta. ` +
          `Tienes ${PHONE_CHANGE_WINDOW_MINUTES} minutos para hacerlo desde <b>Mis Datos</b> y confirmar el número nuevo con un código.</p>` +
          `<p>Si no fuiste tú, cambia tu contraseña y escríbenos de inmediato.</p>`
      );
    }
  } catch (err) {
    logger.warn(`[PhoneChange] No se pudo enviar el aviso por correo: ${String(err)}`);
  }

  return { status: 'AUTHORIZED', until };
}

/** Registra el número nuevo como pendiente. El OTP se envía aparte, a pendingPhone. */
export async function startPhoneChange(userId: string, rawPhone: string): Promise<{ pendingPhone: string; authorizedUntil: Date }> {
  const clean = normalizeBoPhone(rawPhone);
  if (!clean) {
    throw new BadRequestError('Teléfono inválido: 8 dígitos, debe empezar con 6 o 7.', 'INVALID_PHONE');
  }
  const state = await getPhoneState(userId);
  if (!state.canChange || !state.authorizedUntil) {
    throw new ForbiddenError(
      'Para cambiar tu teléfono verificado primero solicítalo por el chat de soporte.',
      'PHONE_CHANGE_NOT_AUTHORIZED'
    );
  }
  if (clean === state.phone) {
    throw new BadRequestError('Ese ya es tu teléfono actual.', 'SAME_PHONE');
  }
  const taken = await prisma.user.findFirst({
    where: { id: { not: userId }, OR: [{ phone: clean }, { pendingPhone: clean }] },
    select: { id: true },
  });
  if (taken) {
    throw new ConflictError('Ese teléfono ya está registrado en otra cuenta.', 'PHONE_IN_USE', 'phone');
  }
  await prisma.user.update({
    where: { id: userId },
    data: { pendingPhone: clean, phoneOtp: null, phoneOtpExpiresAt: null },
  });
  return { pendingPhone: clean, authorizedUntil: state.authorizedUntil };
}

/**
 * Descarta el número pendiente: el verificado anterior no se toca. La ventana de
 * autorización se conserva hasta que venza — así quien se equivocó al escribir
 * el número nuevo puede corregirlo sin tener que pedirle otra vez al bot
 * (que tiene tope diario). Solo commitPhoneChange o el vencimiento la cierran.
 */
export async function cancelPhoneChange(userId: string): Promise<void> {
  await prisma.user.update({
    where: { id: userId },
    data: { pendingPhone: null, phoneOtp: null, phoneOtpExpiresAt: null },
  });
}

/**
 * Confirma el cambio (el OTP ya se validó contra el número nuevo). Compare-and-
 * set atómico: solo aplica si el pendiente sigue siendo el mismo y la ventana
 * no venció, así dos requests a la vez no pueden aplicarlo dos veces.
 */
export async function commitPhoneChange(userId: string, pendingPhone: string): Promise<void> {
  try {
    const [swapped] = await prisma.$transaction([
      prisma.user.updateMany({
        where: { id: userId, pendingPhone, phoneChangeAuthorizedUntil: { gt: new Date() } },
        data: {
          phone: pendingPhone,
          pendingPhone: null,
          phoneChangeAuthorizedUntil: null,
          phoneOtp: null,
          phoneOtpExpiresAt: null,
        },
      }),
    ]);
    if (swapped.count === 0) {
      throw new BadRequestError(
        'El tiempo para cambiar tu teléfono venció. Solicítalo de nuevo por el chat de soporte.',
        'PHONE_CHANGE_EXPIRED'
      );
    }
  } catch (err) {
    if (err instanceof Prisma.PrismaClientKnownRequestError && err.code === 'P2002') {
      throw new ConflictError('Ese teléfono ya está registrado en otra cuenta.', 'PHONE_IN_USE', 'phone');
    }
    throw err;
  }
  // El número nuevo se confirmó por OTP: queda verificado en ambos perfiles
  // (updateMany = no-op seguro para el que el usuario no tenga).
  await Promise.all([
    prisma.caregiverProfile.updateMany({ where: { userId }, data: { phoneVerified: true } }),
    prisma.clientProfile.updateMany({ where: { userId }, data: { phoneVerified: true } }),
  ]);
  logger.info('[PhoneChange] Teléfono cambiado y verificado', { userId });
}
