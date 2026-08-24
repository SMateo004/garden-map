import { Request, Response } from 'express';
import { asyncHandler } from '../../shared/async-handler.js';
import { BadRequestError } from '../../shared/errors.js';
import * as crmService from './caregiver-crm.service.js';
import {
  createWalkInClientBodySchema,
  patchWalkInClientBodySchema,
  createWalkInPetBodySchema,
  patchWalkInPetBodySchema,
  checkInBodySchema,
} from './caregiver-crm.validation.js';

function actingUserId(req: Request): string {
  return req.actingUserId ?? req.user!.userId;
}

// ── Clientes walk-in ─────────────────────────────────────────────────────────

export const listClients = asyncHandler(async (req: Request, res: Response) => {
  const search = typeof req.query.search === 'string' ? req.query.search : undefined;
  const clients = await crmService.listWalkInClients(req.user!.userId, search);
  res.json({ success: true, data: clients });
});

export const getClient = asyncHandler(async (req: Request, res: Response) => {
  const client = await crmService.getWalkInClient(req.user!.userId, req.params.id!);
  res.json({ success: true, data: client });
});

export const createClient = asyncHandler(async (req: Request, res: Response) => {
  const parsed = createWalkInClientBodySchema.safeParse(req.body ?? {});
  if (!parsed.success) throw new BadRequestError(parsed.error.errors[0]?.message ?? 'Datos inválidos', 'VALIDATION_ERROR');
  const client = await crmService.createWalkInClient(req.user!.userId, actingUserId(req), parsed.data);
  res.status(201).json({ success: true, data: client });
});

export const updateClient = asyncHandler(async (req: Request, res: Response) => {
  const parsed = patchWalkInClientBodySchema.safeParse(req.body ?? {});
  if (!parsed.success) throw new BadRequestError(parsed.error.errors[0]?.message ?? 'Datos inválidos', 'VALIDATION_ERROR');
  const client = await crmService.updateWalkInClient(req.user!.userId, req.params.id!, parsed.data);
  res.json({ success: true, data: client });
});

export const deleteClient = asyncHandler(async (req: Request, res: Response) => {
  await crmService.deleteWalkInClient(req.user!.userId, req.params.id!);
  res.json({ success: true });
});

// ── Mascotas walk-in ─────────────────────────────────────────────────────────

export const createPet = asyncHandler(async (req: Request, res: Response) => {
  const parsed = createWalkInPetBodySchema.safeParse(req.body ?? {});
  if (!parsed.success) throw new BadRequestError(parsed.error.errors[0]?.message ?? 'Datos inválidos', 'VALIDATION_ERROR');
  const pet = await crmService.createWalkInPet(req.user!.userId, req.params.clientId!, parsed.data);
  res.status(201).json({ success: true, data: pet });
});

export const updatePet = asyncHandler(async (req: Request, res: Response) => {
  const parsed = patchWalkInPetBodySchema.safeParse(req.body ?? {});
  if (!parsed.success) throw new BadRequestError(parsed.error.errors[0]?.message ?? 'Datos inválidos', 'VALIDATION_ERROR');
  const pet = await crmService.updateWalkInPet(req.user!.userId, req.params.id!, parsed.data);
  res.json({ success: true, data: pet });
});

export const deletePet = asyncHandler(async (req: Request, res: Response) => {
  await crmService.deleteWalkInPet(req.user!.userId, req.params.id!);
  res.json({ success: true });
});

// ── Check-in / check-out ─────────────────────────────────────────────────────

export const checkIn = asyncHandler(async (req: Request, res: Response) => {
  const parsed = checkInBodySchema.safeParse(req.body ?? {});
  if (!parsed.success) throw new BadRequestError(parsed.error.errors[0]?.message ?? 'Datos inválidos', 'VALIDATION_ERROR');
  const visit = await crmService.checkInWalkInPet(
    req.user!.userId, actingUserId(req), req.params.petId!, parsed.data.serviceType, parsed.data.notes
  );
  res.status(201).json({ success: true, data: visit });
});

export const checkOut = asyncHandler(async (req: Request, res: Response) => {
  const visit = await crmService.checkOutWalkInVisit(req.user!.userId, actingUserId(req), req.params.visitId!);
  res.json({ success: true, data: visit });
});

// ── Dashboard de ocupación ────────────────────────────────────────────────────

export const getOccupancy = asyncHandler(async (req: Request, res: Response) => {
  const dashboard = await crmService.getOccupancyDashboard(req.user!.userId);
  res.json({ success: true, data: dashboard });
});
