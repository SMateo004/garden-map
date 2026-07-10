import { Router, Request, Response } from 'express';
import rateLimit from 'express-rate-limit';
import { authMiddleware } from '../../middleware/auth.middleware.js';
import { env } from '../../config/env.js';

const router = Router();

// Antes: sin auth y sin límite propio — cualquiera sin sesión podía golpear
// estos endpoints en bucle y quemar la cuota/facturación de Google Maps con
// la clave del proyecto. Ahora requieren sesión + límite propio (además del
// global de 200/min/IP), ya que cada llamada es una petición pagada a Google.
router.use(authMiddleware);
router.use(
  rateLimit({
    windowMs: 60 * 1000,
    max: 30,
    standardHeaders: true,
    legacyHeaders: false,
    message: { success: false, error: { code: 'TOO_MANY_REQUESTS', message: 'Demasiadas búsquedas de dirección. Espera un minuto.' } },
  })
);

/** GET /api/places/autocomplete?input=X */
router.get('/autocomplete', async (req: Request, res: Response) => {
  const input = String(req.query.input ?? '').trim();
  if (input.length < 3) return res.json({ predictions: [], status: 'ZERO_RESULTS' });

  const url = new URL('https://maps.googleapis.com/maps/api/place/autocomplete/json');
  url.searchParams.set('input', input);
  url.searchParams.set('key', env.GOOGLE_MAPS_KEY);
  url.searchParams.set('components', 'country:bo');
  url.searchParams.set('location', '-17.78,-63.18');
  url.searchParams.set('radius', '30000');
  url.searchParams.set('language', 'es');
  url.searchParams.set('types', 'establishment|geocode');

  try {
    const googleRes = await fetch(url.toString());
    const data = await googleRes.json() as Record<string, unknown>;
    return res.json(data);
  } catch {
    return res.status(502).json({ error: 'places_fetch_failed' });
  }
});

/** GET /api/places/details?place_id=X */
router.get('/details', async (req: Request, res: Response) => {
  const placeId = String(req.query.place_id ?? '').trim();
  if (!placeId) return res.status(400).json({ error: 'place_id required' });

  const url = new URL('https://maps.googleapis.com/maps/api/place/details/json');
  url.searchParams.set('place_id', placeId);
  url.searchParams.set('fields', 'geometry');
  url.searchParams.set('key', env.GOOGLE_MAPS_KEY);

  try {
    const googleRes = await fetch(url.toString());
    const data = await googleRes.json() as Record<string, unknown>;
    return res.json(data);
  } catch {
    return res.status(502).json({ error: 'places_fetch_failed' });
  }
});

export default router;
