import { Request, Response, NextFunction } from 'express';
import { ForbiddenError } from '../shared/errors.js';
import { getStaffContext, type StaffContext } from '../modules/caregiver-staff/caregiver-staff.service.js';
import { auditLog } from '../services/audit.service.js';

declare global {
  namespace Express {
    interface Request {
      staffContext?: StaffContext;
      /** userId real de quien hizo la acción, capturado antes de que actAsOwner lo sustituya — ver captureActingUser. */
      actingUserId?: string;
    }
  }
}

/**
 * Resuelve la membresía de staff del usuario logueado con una consulta
 * fresca a la base en cada request (nunca cacheada en el JWT) — así, si el
 * dueño quita a un empleado, el acceso se corta en el siguiente request, no
 * cuando expire el token. Cuelga el resultado en req.staffContext.
 */
export async function requireStaffMembership(req: Request, _res: Response, next: NextFunction): Promise<void> {
  const ctx = await getStaffContext(req.user!.userId);
  if (!ctx) {
    next(new ForbiddenError('No formás parte del equipo de ninguna empresa'));
    return;
  }
  req.staffContext = ctx;
  next();
}

/**
 * Registra en el audit log qué empleado hizo la acción (con su userId real)
 * ANTES de que actAsOwner sustituya la identidad para el handler reusado —
 * fire-and-forget, nunca bloquea el request. `entity`/`entityIdParam`
 * opcionales para reusar en módulos más allá de reservas (ver caregiver-crm,
 * que loguea contra WalkInVisit con :petId/:visitId en vez de :id).
 */
export function auditStaffAction(action: string, entity: string = 'Booking', entityIdParam: string = 'id') {
  return (req: Request, _res: Response, next: NextFunction): void => {
    const ctx = req.staffContext!;
    auditLog({
      userId: req.user!.userId,
      action,
      entity,
      entityId: req.params[entityIdParam],
      details: { caregiverProfileId: ctx.caregiverProfileId, companyName: ctx.companyName },
    });
    next();
  };
}

/**
 * Captura el userId real de quien hizo la acción ANTES de que actAsOwner lo
 * sustituya — necesario cuando el controller mismo necesita saber "quién
 * hizo esto" (ej. WalkInVisit.checkedInByUserId), no solo el audit log.
 */
export function captureActingUser(req: Request, _res: Response, next: NextFunction): void {
  req.actingUserId = req.user!.userId;
  next();
}

/**
 * Sustituye req.user.userId por el del DUEÑO de la empresa, para que los
 * handlers existentes de booking-service (que resuelven todo a partir de
 * userId) funcionen sin ningún cambio — el staff nunca tiene su propio
 * CaregiverProfile. Debe ir DESPUÉS de requireStaffMembership (y de
 * auditStaffAction, si aplica) en la cadena de middlewares.
 */
export function actAsOwner(req: Request, _res: Response, next: NextFunction): void {
  const ctx = req.staffContext!;
  req.user!.userId = ctx.ownerUserId;
  next();
}
