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

/**
 * GET /api/places/map-snapshot?lat=X&lng=Y — snapshot estático de Google
 * Maps centrado en (lat,lng), con el pin de marca de GARDEN. Tamaño y zoom
 * son FIJOS (no configurables por query param) a propósito — dejar que el
 * cliente elija tamaño/zoom abriría una superficie de abuso de costo sobre
 * una llamada que ya es pagada por request.
 *
 * Consumidor: el mini-mapa del widget de "servicio activo" (ver
 * garden_live_activity.dart / GardenActiveServiceWidget.kt /
 * GardenActivityWidget.swift) — se pide cada ~30s mientras un PASEO está en
 * curso, para ambos roles. Devuelve el PNG crudo (no JSON) para que el
 * cliente lo baje con un solo GET y lo pase tal cual al canal nativo.
 */
router.get('/map-snapshot', async (req: Request, res: Response) => {
  const lat = Number(req.query.lat);
  const lng = Number(req.query.lng);
  if (!Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180) {
    return res.status(400).json({ error: 'lat/lng inválidos' });
  }

  const url = new URL('https://maps.googleapis.com/maps/api/staticmap');
  url.searchParams.set('center', `${lat},${lng}`);
  url.searchParams.set('zoom', '15');
  url.searchParams.set('size', '300x150');
  url.searchParams.set('scale', '2'); // retina — el widget lo muestra a 150x75dp
  url.searchParams.set('maptype', 'roadmap');
  url.searchParams.set('markers', `color:0x778C43|${lat},${lng}`); // verde oliva de marca
  url.searchParams.set('key', env.GOOGLE_MAPS_KEY);

  try {
    const googleRes = await fetch(url.toString());
    if (!googleRes.ok) return res.status(502).json({ error: 'map_snapshot_failed' });
    const buffer = Buffer.from(await googleRes.arrayBuffer());
    res.set('Content-Type', googleRes.headers.get('content-type') ?? 'image/png');
    res.set('Cache-Control', 'private, max-age=15'); // el punto se mueve — no cachear de más
    return res.send(buffer);
  } catch {
    return res.status(502).json({ error: 'map_snapshot_failed' });
  }
});

export default router;
