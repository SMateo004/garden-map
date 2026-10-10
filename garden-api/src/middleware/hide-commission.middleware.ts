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
 *
 * Igual en el otro sentido: la donación voluntaria del dueño es asunto del
 * dueño; el cuidador no la ve (hideDonationFromCaregivers). Ahí el campo no se
 * borra sino que queda en 0, para no romper versiones viejas de la app que lo
 * leen como número.
 */
const HIDDEN_FOR_CLIENTS = ['commissionAmount', 'commissionRate', 'commissionPct', 'caregiverNetAmount'];

/** campo → valor con el que se reemplaza (undefined = se elimina). */
type Redactions = Record<string, number | undefined>;

function strip(value: unknown, redactions: Redactions, depth = 0): unknown {
  if (depth > 12 || value === null || typeof value !== 'object') return value;
  if (Array.isArray(value)) {
    for (const item of value) strip(item, redactions, depth + 1);
    return value;
  }
  if (value instanceof Date) return value;
  const obj = value as Record<string, unknown>;
  for (const key of Object.keys(redactions)) {
    if (!(key in obj)) continue;
    if (redactions[key] === undefined) delete obj[key];
    else obj[key] = redactions[key];
  }
  for (const key of Object.keys(obj)) strip(obj[key], redactions, depth + 1);
  return value;
}

function redactFor(role: 'CLIENT' | 'CAREGIVER', redactions: Redactions) {
  return (req: Request, res: Response, next: NextFunction): void => {
    const originalJson = res.json.bind(res);
    res.json = (body?: unknown) => {
      const user = (req as any).user as { role?: string; activeRole?: string | null } | undefined;
      const effectiveRole = user?.activeRole ?? user?.role;
      if (effectiveRole === role) strip(body, redactions);
      return originalJson(body);
    };
    next();
  };
}

export const hideCommissionFromClients = redactFor(
  'CLIENT',
  Object.fromEntries(HIDDEN_FOR_CLIENTS.map((k) => [k, undefined]))
);

/** El cuidador no ve la donación que el dueño hizo al pagar. */
export const hideDonationFromCaregivers = redactFor('CAREGIVER', { donationAmount: 0 });
