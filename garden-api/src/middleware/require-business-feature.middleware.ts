import type { NextFunction, Request, Response } from 'express';
import prisma from '../config/database.js';
import { ForbiddenError } from '../shared/errors.js';
import { assertFeature, type BusinessFeature } from '../modules/business-features/business-features.service.js';

/**
 * Corta la ruta si el negocio no tiene habilitada la función (la habilita SOLO el admin —
 * business-features.service.ts). Sirve para el dueño y para el empleado: si antes corrió
 * requireStaffMembership se usa la empresa del empleado; si no, el perfil del usuario logueado.
 * Varias funciones = todas obligatorias (ej. recepción del empleado: STAFF_TEAM + RECEPTION).
 */
export function requireBusinessFeature(...features: BusinessFeature[]) {
  return async (req: Request, _res: Response, next: NextFunction): Promise<void> => {
    try {
      let profileId = req.staffContext?.caregiverProfileId;
      if (!profileId) {
        const p = await prisma.caregiverProfile.findUnique({ where: { userId: req.user!.userId }, select: { id: true } });
        if (!p) throw new ForbiddenError('No tienes un perfil de cuidador', 'CAREGIVER_PROFILE_NOT_FOUND');
        profileId = p.id;
      }
      for (const f of features) await assertFeature(profileId, f);
      next();
    } catch (err) {
      next(err);
    }
  };
}
