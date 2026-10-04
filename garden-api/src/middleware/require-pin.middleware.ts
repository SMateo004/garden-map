import type { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import { env } from '../config/env.js';
import prisma from '../config/database.js';

/**
 * PIN de seguridad verificado en el SERVIDOR para mover dinero.
 *
 * Antes el PIN solo gateaba pantallas en la app: /auth/security-pin/verify
 * respondía { valid: true } y la app desbloqueaba, pero cambiar la cuenta
 * bancaria / el QR de cobro / la modalidad de retiro y pedir un retiro solo
 * exigían la sesión. Con un JWT robado se podía redirigir el dinero y
 * retirarlo. Ahora verificar (o crear) el PIN devuelve un token de 15 min que
 * estas rutas exigen en el header X-Pin-Token.
 *
 * Firmado con un secreto DERIVADO (no el de sesión): authMiddleware lo rechaza,
 * así que nunca sirve como token de login.
 *
 * Si el usuario todavía no tiene PIN (registro inicial del cuidador, que carga
 * el banco antes del paso de PIN) no se exige: quien tuviera esa sesión podría
 * crear el PIN de todos modos, así que exigirlo no agrega seguridad.
 */
const PIN_TOKEN_TTL = '15m';
const pinSecret = () => `${env.JWT_SECRET}:security-pin`;

export function issuePinToken(userId: string): string {
  return jwt.sign({ sub: userId, scope: 'security-pin' }, pinSecret(), { expiresIn: PIN_TOKEN_TTL });
}

export function isValidPinToken(token: string | undefined, userId: string): boolean {
  if (!token) return false;
  try {
    const payload = jwt.verify(token, pinSecret()) as { sub?: string; scope?: string };
    return payload.scope === 'security-pin' && payload.sub === userId;
  } catch {
    return false;
  }
}

export async function requirePinToken(req: Request, res: Response, next: NextFunction): Promise<void> {
  try {
    const userId = (req as any).user?.userId as string | undefined;
    if (!userId) {
      res.status(401).json({ success: false, error: { message: 'Token requerido' } });
      return;
    }
    const user = await prisma.user.findUnique({ where: { id: userId }, select: { securityPinHash: true } });
    if (!user?.securityPinHash) {
      next();
      return;
    }
    const header = req.headers['x-pin-token'];
    const token = Array.isArray(header) ? header[0] : header;
    if (!isValidPinToken(token, userId)) {
      res.status(403).json({
        success: false,
        error: { code: 'PIN_REQUIRED', message: 'Confirma con tu PIN para continuar.' },
      });
      return;
    }
    next();
  } catch (err) {
    next(err);
  }
}
