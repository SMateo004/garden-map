import { Router, Request, Response } from 'express';

const router = Router();

const GOOGLE_MAPS_KEY = process.env.GOOGLE_MAPS_KEY ?? 'AIzaSyB8SgAWB79TjJVXexd4byx8U8_T5NNwQV0';

/** GET /api/places/autocomplete?input=X */
router.get('/autocomplete', async (req: Request, res: Response) => {
  const input = String(req.query.input ?? '').trim();
  if (input.length < 3) return res.json({ predictions: [], status: 'ZERO_RESULTS' });

  const url = new URL('https://maps.googleapis.com/maps/api/place/autocomplete/json');
  url.searchParams.set('input', input);
  url.searchParams.set('key', GOOGLE_MAPS_KEY);
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
  url.searchParams.set('key', GOOGLE_MAPS_KEY);

  try {
    const googleRes = await fetch(url.toString());
    const data = await googleRes.json() as Record<string, unknown>;
    return res.json(data);
  } catch {
    return res.status(502).json({ error: 'places_fetch_failed' });
  }
});

export default router;
