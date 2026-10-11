/**
 * Nombre, apellido y fecha de nacimiento son la identidad de la persona en Garden: se verifican con el carnet,
 * respaldan el registro en la blockchain y no pueden ser distintos entre lo que se verificó y lo que se muestra.
 * Por eso, una vez cargados, el usuario ya no los edita: solo un administrador (PATCH /admin/users/:id/identity).
 *
 * Excepciones, para no dejar a nadie sin poder completar su registro:
 *  - El campo todavía no tiene un valor real (vacío, "-" de las cuentas de Google sin apellido, sin fecha).
 *  - Cuidador con el registro sin terminar (profileStatus INCOMPLETE) y sin identidad verificada: aún está
 *    llenando sus datos y puede corregir un error de tipeo.
 *
 * Reenviar el mismo valor que ya tiene es válido (la app manda todos los campos en cada guardado).
 */
import prisma from '../../config/database.js';
import { ForbiddenError } from '../../shared/errors.js';

export interface IdentityInput {
  firstName?: string | null;
  lastName?: string | null;
  dateOfBirth?: Date | string | null;
}

const norm = (v: string | null | undefined) => (v ?? '').trim().replace(/\s+/g, ' ').toLowerCase();
const isPlaceholderName = (v: string | null | undefined) => {
  const t = (v ?? '').trim();
  return t === '' || t === '-';
};
const dayOf = (v: Date | string | null | undefined): string | null => {
  if (!v) return null;
  const d = v instanceof Date ? v : new Date(v);
  return isNaN(d.getTime()) ? null : d.toISOString().slice(0, 10);
};

/** ¿Está el usuario todavía completando su registro de cuidador (sin identidad verificada)? */
async function isRegistrationOpen(userId: string): Promise<boolean> {
  const profile = await prisma.caregiverProfile.findUnique({
    where: { userId },
    select: { profileStatus: true, identityVerificationStatus: true },
  });
  if (!profile) return false;
  return (profile.profileStatus ?? 'INCOMPLETE') === 'INCOMPLETE' && profile.identityVerificationStatus !== 'VERIFIED';
}

/**
 * Lanza IDENTITY_LOCKED si [input] intenta cambiar un dato de identidad ya cargado.
 * Devuelve sin hacer nada si no cambia nada o si el campo todavía se puede completar.
 */
export async function assertIdentityEditable(userId: string, input: IdentityInput): Promise<void> {
  const wantsFirst = typeof input.firstName === 'string' && input.firstName.trim() !== '';
  const wantsLast = typeof input.lastName === 'string' && input.lastName.trim() !== '';
  const wantsDob = dayOf(input.dateOfBirth) !== null;
  if (!wantsFirst && !wantsLast && !wantsDob) return;

  const user = await prisma.user.findUnique({
    where: { id: userId },
    select: { firstName: true, lastName: true, dateOfBirth: true },
  });
  if (!user) return;

  const changes: string[] = [];
  if (wantsFirst && !isPlaceholderName(user.firstName) && norm(input.firstName) !== norm(user.firstName)) changes.push('nombre');
  if (wantsLast && !isPlaceholderName(user.lastName) && norm(input.lastName) !== norm(user.lastName)) changes.push('apellido');
  if (wantsDob && user.dateOfBirth && dayOf(input.dateOfBirth) !== dayOf(user.dateOfBirth)) changes.push('fecha de nacimiento');
  if (changes.length === 0) return;

  if (await isRegistrationOpen(userId)) return;

  throw new ForbiddenError(
    'Tu nombre, apellido y fecha de nacimiento están verificados y no se pueden modificar. Si hay un error, escríbenos por soporte y un administrador lo corrige.',
    'IDENTITY_LOCKED'
  );
}

/** Qué datos de identidad están bloqueados para este usuario (la app los muestra sin edición). */
export async function getIdentityLock(userId: string): Promise<{ firstName: boolean; lastName: boolean; dateOfBirth: boolean }> {
  const user = await prisma.user.findUnique({
    where: { id: userId },
    select: { firstName: true, lastName: true, dateOfBirth: true },
  });
  if (!user || (await isRegistrationOpen(userId))) return { firstName: false, lastName: false, dateOfBirth: false };
  return {
    firstName: !isPlaceholderName(user.firstName),
    lastName: !isPlaceholderName(user.lastName),
    dateOfBirth: user.dateOfBirth != null,
  };
}
