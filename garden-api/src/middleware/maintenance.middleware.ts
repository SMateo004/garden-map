import type { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import { env } from '../config/env.js';
import { getBoolSetting } from '../utils/settings-cache.js';

/**
 * Maintenance-mode middleware.
 *
 * When the `maintenanceMode` AppSetting is true the API responds 503 to every
 * request **except**:
 *   - GET /health  — Render needs this to stay green
 *   - /api/admin/* — admins must be able to disable maintenance mode
 *   - /api/payments/webhook — Stripe webhooks must never be dropped
 *   - GET /api/settings (+ price-limits) — the splash screen and every
 *     screen's HTTP client read this to *detect* maintenance mode in the
 *     first place. Blocking it makes the maintenance screen unreachable:
 *     `/api/settings` would itself 503 with an error body that doesn't
 *     contain `maintenanceMode`, so the client silently treats it as false.
 *   - Any request carrying a VALID admin JWT — an admin using the rest of
 *     the app (not just /api/admin/*) shouldn't get bounced to the
 *     maintenance screen mid-session while they're the one managing the
 *     incident. Only checked if a Bearer token is present; no token or a
 *     non-admin role falls through to the normal block below.
 *
 * The setting is read from the settings-cache (30 s TTL) so there is no DB
 * hit on every request under normal operation.
 */
export async function maintenanceMiddleware(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  // Always allow through
  if (
    req.path === '/health' ||
    req.path.startsWith('/api/admin') ||
    req.path.startsWith('/api/payments/webhook') ||
    req.path === '/api/settings' ||
    req.path === '/api/settings/price-limits'
  ) {
    return next();
  }

  if (isAdminRequest(req)) {
    return next();
  }

  try {
    const inMaintenance = await getBoolSetting('maintenanceMode', false);
    if (inMaintenance) {
      res.status(503).json({
        success: false,
        error: {
          code: 'MAINTENANCE_MODE',
          message: 'GARDEN está en mantenimiento. Volvemos pronto 🐾',
        },
      });
      return;
    }
  } catch {
    // If the settings check itself fails, fail-open so the API keeps running
  }

  next();
}

/** Ligero: solo verifica firma + rol, no revisa blacklist (eso lo hace authMiddleware normalmente). */
function isAdminRequest(req: Request): boolean {
  const header = req.headers.authorization;
  if (!header || !header.startsWith('Bearer ')) return false;
  try {
    const payload = jwt.verify(header.slice(7), env.JWT_SECRET) as { role?: string; activeRole?: string };
    return payload.role === 'ADMIN' || payload.activeRole === 'ADMIN';
  } catch {
    return false;
  }
}
