import type { Request, Response, NextFunction } from 'express';
import { getBoolSetting } from '../utils/settings-cache.js';

/**
 * Maintenance-mode middleware.
 *
 * When the `maintenanceMode` AppSetting is true the API responds 503 to every
 * request **except**:
 *   - GET /health  — Render needs this to stay green
 *   - /api/admin/* — admins must be able to disable maintenance mode
 *   - /api/payments/webhook — Stripe webhooks must never be dropped
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
    req.path.startsWith('/api/payments/webhook')
  ) {
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
