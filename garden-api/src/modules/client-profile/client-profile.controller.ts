/**
 * Controlador: gestión de perfil de cliente (dueño de mascota).
 * - GET /api/client/my-profile
 * - PATCH /api/client/profile
 */

import { Request, Response } from 'express';
import { asyncHandler } from '../../shared/async-handler.js';
import * as clientProfileService from './client-profile.service.js';
import { patchClientProfileSchema } from './client-profile.validation.js';
import prisma from '../../config/database.js';

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

export const getFavorites = asyncHandler(async (req: Request, res: Response) => {
  const userId = req.user!.userId;
  const result = await clientProfileService.getFavorites(userId);
  res.json({ success: true, data: result });
});

export const toggleFavorite = asyncHandler(async (req: Request, res: Response) => {
  const userId = req.user!.userId;
  const caregiverId = req.params.caregiverId;

  if (!caregiverId) {
    res.status(400).json({ success: false, error: 'caregiverId es requerido' });
    return;
  }

  const result = await clientProfileService.toggleFavorite(userId, caregiverId as string);
  res.json({ success: true, data: result });
});

/** GET /api/client/my-reviews — calificaciones escritas por el cliente logueado. */
export const getMyReviews = asyncHandler(async (req: Request, res: Response) => {
  const userId = req.user!.userId;
  const reviews = await prisma.review.findMany({
    where: { clientId: userId, isSystemGenerated: false },
    orderBy: { createdAt: 'desc' },
    select: {
      id: true,
      rating: true,
      comment: true,
      serviceType: true,
      createdAt: true,
      caregiverResponse: true,
      caregiver: {
        select: {
          id: true,
          bio: true,
          profilePhoto: true,
          user: { select: { firstName: true, lastName: true } },
        },
      },
    },
  });
  res.json({ success: true, data: reviews });
});

/** GET /api/client/my-donations — resumen de donaciones del cliente logueado
 *  (tarjeta de "Donador" en el perfil — 100% simbólico/visual, pero con el
 *  monto real acumulado en la tabla Donation). */
export const getMyDonationsSummary = asyncHandler(async (req: Request, res: Response) => {
  const userId = req.user!.userId;
  const agg = await prisma.donation.aggregate({
    where: { clientId: userId },
    _sum: { amount: true },
    _count: { _all: true },
  });
  res.json({
    success: true,
    data: {
      totalAmount: Number(agg._sum.amount ?? 0),
      count: agg._count._all,
    },
  });
});

/** Sin caracteres ambiguos (0/O, 1/I/L) para que se pueda dictar/anotar a mano sin errores. */
const DONOR_CODE_CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
function generateDonorCode(): string {
  let code = '';
  for (let i = 0; i < 8; i++) {
    code += DONOR_CODE_CHARS[Math.floor(Math.random() * DONOR_CODE_CHARS.length)];
  }
  return `GRD-${code}`;
}

/** GET /api/client/donor-card — tarjeta de donador completa (reverso de la
 *  billetera): código único (se genera solo, fijo de por vida), total
 *  donado + detalle, y uso del código en negocios asociados. */
export const getDonorCard = asyncHandler(async (req: Request, res: Response) => {
  const userId = req.user!.userId;

  const existing = await prisma.user.findUnique({ where: { id: userId }, select: { donorCode: true } });
  let donorCode = existing?.donorCode ?? null;

  if (!donorCode) {
    for (let attempt = 0; attempt < 5 && !donorCode; attempt++) {
      try {
        const updated = await prisma.user.update({
          where: { id: userId },
          data: { donorCode: generateDonorCode() },
          select: { donorCode: true },
        });
        donorCode = updated.donorCode;
      } catch (err: any) {
        if (err?.code !== 'P2002') throw err; // colisión de código único → reintentar
      }
    }
  }

  const [agg, donations, redemptions, redemptionCount] = await Promise.all([
    prisma.donation.aggregate({ where: { clientId: userId }, _sum: { amount: true }, _count: { _all: true } }),
    prisma.donation.findMany({
      where: { clientId: userId },
      orderBy: { createdAt: 'desc' },
      select: { amount: true, createdAt: true },
      take: 50,
    }),
    prisma.donorCodeRedemption.findMany({
      where: { userId },
      orderBy: { redeemedAt: 'desc' },
      select: { businessName: true, redeemedAt: true },
      take: 50,
    }),
    prisma.donorCodeRedemption.count({ where: { userId } }),
  ]);

  res.json({
    success: true,
    data: {
      code: donorCode,
      totalDonated: Number(agg._sum.amount ?? 0),
      donationCount: agg._count._all,
      donations: donations.map((d) => ({ amount: Number(d.amount), date: d.createdAt })),
      redemptionCount,
      redemptions: redemptions.map((r) => ({ businessName: r.businessName, date: r.redeemedAt })),
    },
  });
});
