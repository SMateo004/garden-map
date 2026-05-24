import { Router } from 'express';
import { authMiddleware } from '../../middleware/auth.middleware.js';
import { asyncHandler } from '../../shared/async-handler.js';
import prisma from '../../config/database.js';

const router = Router();

function haversineKm(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 6371;
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLng = (lng2 - lng1) * Math.PI / 180;
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) * Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

/** GET /api/vets/nearest?lat=X&lng=Y — devuelve las 3 veterinarias activas más cercanas. */
router.get(
  '/nearest',
  authMiddleware,
  asyncHandler(async (req, res) => {
    const lat = parseFloat(req.query['lat'] as string);
    const lng = parseFloat(req.query['lng'] as string);
    if (isNaN(lat) || isNaN(lng)) {
      res.status(400).json({ success: false, error: { message: 'lat y lng son requeridos' } });
      return;
    }
    const vets = await (prisma as any).vetClinic.findMany({ where: { isActive: true } });
    const sorted = vets
      .map((v: any) => ({ ...v, distanceKm: haversineKm(lat, lng, v.lat, v.lng) }))
      .sort((a: any, b: any) => a.distanceKm - b.distanceKm)
      .slice(0, 3);
    res.json({ success: true, data: sorted });
  })
);

export default router;
