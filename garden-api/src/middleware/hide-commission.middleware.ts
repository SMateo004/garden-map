import type { Request, Response, NextFunction } from 'express';

/**
 * La comisión de GARDEN nunca se muestra al cliente (ver CLAUDE.md y
 * pricing.service.ts): el cliente ve un precio final, sin desglose de comisión.
 * bookingToResponse() y otros serializadores incluyen `commissionAmount`
 * porque el cuidador y el admin la necesitan para calcular la ganancia, así que
 * las respuestas que recibe un CLIENT la llevaban igual (no se mostraba, pero
 * quedaba visible para cualquiera que inspeccionara la respuesta).
 *
 * Este middleware envuelve res.json y, si quien pide es un CLIENT (rol
 * efectivo), quita esos campos de cualquier objeto de la respuesta. Se evalúa
 * al responder, cuando authMiddleware ya pobló req.user.
 */
const HIDDEN_FOR_CLIENTS = ['commissionAmount', 'commissionRate', 'commissionPct', 'caregiverNetAmount'];

function strip(value: unknown, depth = 0): unknown {
  if (depth > 12 || value === null || typeof value !== 'object') return value;
  if (Array.isArray(value)) {
    for (const item of value) strip(item, depth + 1);
    return value;
  }
  if (value instanceof Date) return value;
  const obj = value as Record<string, unknown>;
  for (const key of HIDDEN_FOR_CLIENTS) {
    if (key in obj) delete obj[key];
  }
  for (const key of Object.keys(obj)) strip(obj[key], depth + 1);
  return value;
}

export function hideCommissionFromClients(req: Request, res: Response, next: NextFunction): void {
  const originalJson = res.json.bind(res);
  res.json = (body?: unknown) => {
    const user = (req as any).user as { role?: string; activeRole?: string | null } | undefined;
    const effectiveRole = user?.activeRole ?? user?.role;
    if (effectiveRole === 'CLIENT') strip(body);
    return originalJson(body);
  };
  next();
}
