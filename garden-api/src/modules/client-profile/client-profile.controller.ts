/**
 * Controlador: gestión de perfil de cliente (dueño de mascota).
 * - GET /api/client/my-profile
 * - PATCH /api/client/profile
 */

import { Request, Response } from 'express';
import { asyncHandler } from '../../shared/async-handler.js';
import * as clientProfileService from './client-profile.service.js';
import { patchClientProfileSchema } from './client-profile.validation.js';

/** GET /api/client/my-profile - Perfil del cliente logueado. */
export const getMyProfile = asyncHandler(async (req: Request, res: Response) => {
  const userId = req.user!.userId;
  const profile = await clientProfileService.getMyProfile(userId);
  if (!profile) {
    res.status(404).json({
      success: false,
      error: { code: 'CLIENT_PROFILE_NOT_FOUND', message: 'No tienes perfil de cliente' },
    });
    return;
  }
  res.json({ success: true, data: profile });
});

/** PATCH /api/client/profile - Actualización de datos del dueño (address, phone). */
export const patchProfile = asyncHandler(async (req: Request, res: Response) => {
  const userId = req.user!.userId;
  const body = patchClientProfileSchema.parse(req.body);
  const result = await clientProfileService.patchProfile(userId, body);
  res.json({ success: true, data: result });
});
