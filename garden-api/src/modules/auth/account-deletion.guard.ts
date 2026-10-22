/**
 * Qué impide eliminar una cuenta (auditorías 2026-10-11 y 2026-10-12).
 *
 * Antes cada camino de baja revisaba cosas distintas: la baja del dueño no miraba los retiros en
 * curso (el saldo reservado para el retiro se "donaba" a GARDEN y el retiro quedaba varado), y la
 * aprobación de baja de un cuidador no miraba nada — un admin podía aprobarla con una mascota a su
 * cargo (servicio en curso) o con una disputa abierta. Ahora los tres caminos (baja propia del
 * dueño, pedido y aprobación de baja del cuidador) usan esta misma revisión. La baja forzada por un
 * admin (deleteUserAccountByAdmin) ya tenía la suya, igual de estricta.
 */
import prisma from '../../config/database.js';
import { BadRequestError } from '../../shared/errors.js';

const ACTIVE_STATUSES = [
  'PENDING_MG',
  'PENDING_PAYMENT',
  'PAYMENT_PENDING_APPROVAL',
  'WAITING_CAREGIVER_APPROVAL',
  'SLOT_CONFLICT',
  'CONFIRMED',
  'IN_PROGRESS',
] as const;

/** Qué cara de la cuenta se va: ALL = la cuenta entera; CAREGIVER = solo el perfil de cuidador. */
export type DeletionScope = 'ALL' | 'CAREGIVER';

export interface DeletionBlockers {
  activeAsClient: number;
  activeAsCaregiver: number;
  inProgressAsCaregiver: number;
  openDisputes: number;
  pendingWithdrawals: number;
}

export async function getDeletionBlockers(userId: string, scope: DeletionScope = 'ALL'): Promise<DeletionBlockers> {
  const profile = await prisma.caregiverProfile.findUnique({ where: { userId }, select: { id: true } });
  const caregiverId = profile?.id;
  const asClient = scope === 'ALL';
  const bookingSides = [
    ...(asClient ? [{ clientId: userId }] : []),
    ...(caregiverId ? [{ caregiverId }] : []),
  ];
  const [activeAsClient, activeAsCaregiver, inProgressAsCaregiver, openDisputes, pendingWithdrawals] = await Promise.all([
    asClient ? prisma.booking.count({ where: { clientId: userId, status: { in: [...ACTIVE_STATUSES] } } }) : 0,
    caregiverId ? prisma.booking.count({ where: { caregiverId, status: { in: [...ACTIVE_STATUSES] } } }) : 0,
    caregiverId ? prisma.booking.count({ where: { caregiverId, status: 'IN_PROGRESS' } }) : 0,
    bookingSides.length
      ? prisma.dispute.count({ where: { status: { in: ['OPEN', 'IN_REVIEW'] }, booking: { OR: bookingSides } } })
      : 0,
    // Solo cuenta si se va la cuenta entera: con la baja de solo el perfil de cuidador el saldo sigue en la cuenta.
    asClient
      ? prisma.walletTransaction.count({ where: { userId, type: 'WITHDRAWAL', status: { in: ['PENDING', 'PROCESSING'] } } })
      : 0,
  ]);
  return { activeAsClient, activeAsCaregiver, inProgressAsCaregiver, openDisputes, pendingWithdrawals };
}

/** Lanza un error con el motivo concreto si algo impide la baja. `who` cambia la redacción (el usuario o el admin). */
export async function assertNoDeletionBlockers(userId: string, scope: DeletionScope = 'ALL', who: 'self' | 'admin' = 'self'): Promise<void> {
  const b = await getDeletionBlockers(userId, scope);
  const self = who === 'self';
  if (b.inProgressAsCaregiver > 0) {
    throw new BadRequestError(
      self
        ? 'Tienes un servicio en curso. Termínalo antes de eliminar tu cuenta.'
        : 'El cuidador tiene un servicio en curso (una mascota a su cargo). No se puede aprobar la baja hasta que termine.',
      'DELETION_SERVICE_IN_PROGRESS'
    );
  }
  if (b.activeAsClient + b.activeAsCaregiver > 0) {
    throw new BadRequestError(
      self
        ? 'Tienes reservas activas o pendientes. Debes esperar a que finalicen antes de eliminar tu cuenta.'
        : `Tiene ${b.activeAsClient + b.activeAsCaregiver} reserva(s) activa(s). Deben terminar o cancelarse antes de aprobar la baja.`,
      'PENDING_BOOKINGS'
    );
  }
  if (b.openDisputes > 0) {
    throw new BadRequestError(
      self
        ? 'Tienes una disputa abierta. Debes esperar a que se resuelva antes de eliminar tu cuenta.'
        : 'Tiene una disputa abierta. Resuélvela antes de aprobar la baja.',
      'PENDING_DISPUTES'
    );
  }
  if (b.pendingWithdrawals > 0) {
    throw new BadRequestError(
      self
        ? 'Tienes un retiro en curso. Espera a que se complete (o cancélalo) antes de eliminar tu cuenta.'
        : 'Tiene un retiro en curso. Procésalo o recházalo antes de aprobar la baja.',
      'PENDING_WITHDRAWAL'
    );
  }
}
