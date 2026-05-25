import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import { env } from '../config/env.js';
import { UnauthorizedError, ForbiddenError } from '../shared/errors.js';
import logger from '../shared/logger.js';
import { isTokenBlacklisted } from '../services/token-blacklist.service.js';

export interface JwtPayload {
  userId: string;
  role: string;
  /** Rol activo en sesión (puede diferir del rol permanente durante un cambio de rol). */
  activeRole?: string;
}

declare global {
  namespace Express {
    interface Request {
      user?: JwtPayload;
    }
  }
}

export function authMiddleware(req: Request, _res: Response, next: NextFunction): void {
  const header = req.headers.authorization;
  if (!header || !header.startsWith('Bearer ')) {
    logger.warn('Auth: 401 — sin token', { path: req.path, method: req.method });
    next(new UnauthorizedError('Token requerido'));
    return;
  }
  const token = header.slice(7);
  try {
    const payload = jwt.verify(token, env.JWT_SECRET) as JwtPayload;
    req.user = payload;
    // Async blacklist check — run after basic JWT validation to avoid
    // hitting Redis on every invalid token
    isTokenBlacklisted(token).then(revoked => {
      if (revoked) {
        logger.warn('Auth: 401 — token revocado', { path: req.path, userId: payload.userId });
        next(new UnauthorizedError('Sesión cerrada. Vuelve a iniciar sesión.'));
      } else {
        next();
      }
    }).catch((err) => {
      // Fail-closed: if the blacklist check throws (e.g., Redis configured but down),
      // block the request rather than silently allow a potentially revoked token.
      logger.error('Auth: blacklist check failed — blocking request', {
        path: req.path,
        userId: payload.userId,
        error: (err as Error).message,
      });
      next(new UnauthorizedError('No se pudo verificar la sesión. Intenta de nuevo.'));
    });
  } catch {
    logger.warn('Auth: 401 — token inválido o expirado', { path: req.path, method: req.method });
    next(new UnauthorizedError('Token inválido o expirado'));
  }
}

export function requireRole(...roles: string[]) {
  return (req: Request, _res: Response, next: NextFunction): void => {
    if (!req.user) {
      next(new UnauthorizedError());
      return;
    }
    const effectiveRole = req.user.activeRole ?? req.user.role;
    if (!roles.includes(effectiveRole)) {
      next(new ForbiddenError('Sin permisos para esta acción'));
      return;
    }
    next();
  };
}
