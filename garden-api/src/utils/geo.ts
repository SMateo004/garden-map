import { Prisma } from '@prisma/client';
import prisma from '../config/database.js';

interface LatLng {
  lat: number;
  lng: number;
}

/**
 * Ray casting estándar — misma implementación que
 * garden-app/lib/widgets/address_section.dart (_pointInPolygon), para que el
 * resultado del cliente y el del servidor coincidan siempre. Ver ese archivo
 * si se toca esta función — deben mantenerse en paridad.
 */
function pointInPolygon(lat: number, lng: number, polygon: LatLng[]): boolean {
  let inside = false;
  for (let i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    const pi = polygon[i]!, pj = polygon[j]!;
    const xi = pi.lng, yi = pi.lat;
    const xj = pj.lng, yj = pj.lat;
    const intersect = yi > lat !== yj > lat && lng < ((xj - xi) * (lat - yi)) / (yj - yi) + xi;
    if (intersect) inside = !inside;
  }
  return inside;
}

/**
 * Única fuente de verdad server-side para resolver a qué CityZone pertenece
 * un punto — usada tanto al registrar/actualizar un perfil (autoritativa,
 * ignora el zoneId que mande el cliente) como al re-chequear perfiles sin
 * zona cuando un admin agrega o edita un polígono. Devuelve null si el punto
 * no cae en ningún polígono activo de esa ciudad (Garden todavía no cubre
 * esa zona — caso esperado, no es un error).
 */
export async function matchZoneForPoint(
  cityId: string,
  lat: number,
  lng: number
): Promise<{ id: string; key: string } | null> {
  const zones = await prisma.cityZone.findMany({
    where: { cityId, active: true, points: { not: Prisma.JsonNull } },
    select: { id: true, key: true, points: true },
  });
  for (const zone of zones) {
    const points = zone.points as unknown as LatLng[] | null;
    if (!points || points.length < 4) continue;
    if (pointInPolygon(lat, lng, points)) {
      return { id: zone.id, key: zone.key };
    }
  }
  return null;
}
