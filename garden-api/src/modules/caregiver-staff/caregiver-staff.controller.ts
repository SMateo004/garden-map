import { Request, Response } from 'express';
import { asyncHandler } from '../../shared/async-handler.js';
import { BadRequestError } from '../../shared/errors.js';
import * as caregiverStaffService from './caregiver-staff.service.js';
import { createInviteBodySchema, registerStaffBodySchema, removalReasonBodySchema } from './caregiver-staff.validation.js';

// ── Gestión del dueño ────────────────────────────────────────────────────────

export const createInvite = asyncHandler(async (req: Request, res: Response) => {
  const parsed = createInviteBodySchema.safeParse(req.body ?? {});
  if (!parsed.success) {
    throw new BadRequestError(parsed.error.errors[0]?.message ?? 'Datos inválidos', 'VALIDATION_ERROR');
  }
  const invite = await caregiverStaffService.generateInviteCode(req.user!.userId, parsed.data.label, parsed.data.expiresInDays);
  res.status(201).json({ success: true, data: invite });
});

export const listInvites = asyncHandler(async (req: Request, res: Response) => {
  const invites = await caregiverStaffService.listInvites(req.user!.userId);
  res.json({ success: true, data: invites });
});

export const revokeInvite = asyncHandler(async (req: Request, res: Response) => {
  await caregiverStaffService.revokeInvite(req.user!.userId, req.params.id!);
  res.json({ success: true });
});

export const listStaffMembers = asyncHandler(async (req: Request, res: Response) => {
  const members = await caregiverStaffService.listStaffMembers(req.user!.userId);
  res.json({ success: true, data: members });
});

export const removeStaffMember = asyncHandler(async (req: Request, res: Response) => {
  const parsed = removalReasonBodySchema.safeParse(req.body ?? {});
  if (!parsed.success) {
    throw new BadRequestError(parsed.error.errors[0]?.message ?? 'Datos inválidos', 'VALIDATION_ERROR');
  }
  await caregiverStaffService.removeStaffMember(req.user!.userId, req.params.id!, parsed.data.reason);
  res.json({ success: true });
});

export const suspendStaffMember = asyncHandler(async (req: Request, res: Response) => {
  await caregiverStaffService.suspendStaffMember(req.user!.userId, req.params.id!);
  res.json({ success: true });
});

export const reactivateStaffMember = asyncHandler(async (req: Request, res: Response) => {
  await caregiverStaffService.reactivateStaffMember(req.user!.userId, req.params.id!);
  res.json({ success: true });
});

// ── Autoservicio del empleado ────────────────────────────────────────────────

export const previewInvite = asyncHandler(async (req: Request, res: Response) => {
  const result = await caregiverStaffService.previewInvite(req.params.code!);
  res.json({ success: true, data: result });
});

export const registerStaff = asyncHandler(async (req: Request, res: Response) => {
  const parsed = registerStaffBodySchema.safeParse(req.body ?? {});
  if (!parsed.success) {
    throw new BadRequestError(parsed.error.errors[0]?.message ?? 'Datos inválidos', 'VALIDATION_ERROR');
  }
  const result = await caregiverStaffService.registerStaffMember(parsed.data);
  res.status(201).json({ success: true, data: result });
});

// ── Operativo del empleado ───────────────────────────────────────────────────

/** GET /api/caregiver-staff/whoami — para que la pantalla del staff sepa a qué empresa pertenece. */
export const whoami = asyncHandler(async (req: Request, res: Response) => {
  const ctx = req.staffContext!;
  res.json({ success: true, data: { companyName: ctx.companyName, staffMemberId: ctx.staffMemberId } });
});
