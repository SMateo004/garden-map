/**
 * Controlador: CRUD de servicios extra (ExtraService).
 * - GET /api/caregiver/extra-services
 * - POST /api/caregiver/extra-services
 * - PATCH /api/caregiver/extra-services/:id
 * - DELETE /api/caregiver/extra-services/:id
 */

import { Request, Response } from 'express';
import { asyncHandler } from '../../shared/async-handler.js';
import * as extraServiceService from './extra-service.service.js';
import { createExtraServiceSchema, patchExtraServiceSchema } from './extra-service.validation.js';

export const listMyExtraServices = asyncHandler(async (req: Request, res: Response) => {
  const userId = req.user!.userId;
  const data = await extraServiceService.listMyExtraServices(userId);
  res.json({ success: true, data });
});

export const createExtraService = asyncHandler(async (req: Request, res: Response) => {
  const userId = req.user!.userId;
  const body = createExtraServiceSchema.parse(req.body);
  const data = await extraServiceService.createExtraService(userId, body);
  res.status(201).json({ success: true, data });
});

export const patchExtraService = asyncHandler(async (req: Request, res: Response) => {
  const userId = req.user!.userId;
  const { id } = req.params;
  const body = patchExtraServiceSchema.parse(req.body);
  const data = await extraServiceService.patchExtraService(userId, id, body);
  res.json({ success: true, data });
});

export const deleteExtraService = asyncHandler(async (req: Request, res: Response) => {
  const userId = req.user!.userId;
  const { id } = req.params;
  const data = await extraServiceService.deleteExtraService(userId, id);
  res.json({ success: true, data });
});
