/**
 * "Avísame cuando lleguen a mi ciudad": un dueño que abre el marketplace en una ciudad donde todavía no hay
 * cuidadores deja su interés. Se guarda en `AuditLog` (action CITY_INTEREST) — sin cambios de esquema — y el
 * admin lo cuenta por ciudad para decidir dónde reclutar cuidadores primero.
 *
 *  - POST /api/city-interest { cityId }  → idempotente: un usuario cuenta una sola vez por ciudad.
 *  - GET  /api/city-interest/mine?cityId → ¿ya pedí que me avisen en esta ciudad?
 *  - GET  /api/city-interest/summary     → ADMIN: interesados por ciudad.
 */
import { Router } from 'express';
import prisma from '../../config/database.js';
import { authMiddleware, requireRole } from '../../middleware/auth.middleware.js';

export const CITY_INTEREST_ACTION = 'CITY_INTEREST';

const router = Router();
router.use(authMiddleware);

function userIdOf(req: any): string {
  return req.user.userId as string;
}

async function alreadyInterested(userId: string, cityId: string): Promise<boolean> {
  const found = await prisma.auditLog.findFirst({
    where: { userId, action: CITY_INTEREST_ACTION, entity: 'City', entityId: cityId },
    select: { id: true },
  });
  return !!found;
}

router.post('/', async (req, res, next) => {
  try {
    const cityId = typeof req.body?.cityId === 'string' ? req.body.cityId.trim() : '';
    if (!cityId || cityId.length > 100) {
      return res.status(400).json({ success: false, error: { code: 'VALIDATION_ERROR', message: 'cityId requerido' } });
    }
    const city = await prisma.city.findUnique({ where: { id: cityId }, select: { id: true, name: true } });
    if (!city) {
      return res.status(404).json({ success: false, error: { code: 'NOT_FOUND', message: 'Ciudad no encontrada' } });
    }
    const userId = userIdOf(req);
    if (!(await alreadyInterested(userId, city.id))) {
      await prisma.auditLog.create({
        data: {
          userId,
          action: CITY_INTEREST_ACTION,
          entity: 'City',
          entityId: city.id,
          details: JSON.stringify({ cityName: city.name }),
          ip: req.ip?.slice(0, 45),
        },
      });
    }
    res.json({ success: true, data: { interested: true } });
  } catch (err) {
    next(err);
  }
});

router.get('/mine', async (req, res, next) => {
  try {
    const cityId = typeof req.query.cityId === 'string' ? req.query.cityId : '';
    if (!cityId) return res.json({ success: true, data: { interested: false } });
    res.json({ success: true, data: { interested: await alreadyInterested(userIdOf(req), cityId) } });
  } catch (err) {
    next(err);
  }
});

router.get('/summary', requireRole('ADMIN'), async (_req, res, next) => {
  try {
    const rows = await prisma.auditLog.groupBy({
      by: ['entityId'],
      where: { action: CITY_INTEREST_ACTION, entity: 'City' },
      _count: { _all: true },
    });
    const cities = await prisma.city.findMany({
      where: { id: { in: rows.map((r) => r.entityId).filter((x): x is string => !!x) } },
      select: { id: true, name: true },
    });
    const nameOf = new Map(cities.map((c) => [c.id, c.name]));
    const data = rows
      .map((r) => ({ cityId: r.entityId, cityName: nameOf.get(r.entityId ?? '') ?? '—', interested: r._count._all }))
      .sort((a, b) => b.interested - a.interested);
    res.json({ success: true, data });
  } catch (err) {
    next(err);
  }
});

export default router;
