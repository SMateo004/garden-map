/**
 * Límites de envío y verificación de códigos OTP (teléfono y correo).
 *
 * Antes cada límite contaba por IP. En Bolivia las operadoras móviles comparten
 * pocas IPs públicas entre muchísimos usuarios (CGNAT): con "3 códigos por hora
 * por IP", tres personas pidiendo su código desde la misma red bloqueaban al
 * resto. Todas estas rutas exigen sesión, así que el límite real se cuenta por
 * usuario; la IP queda solo como techo amplio de costo contra un mismo origen
 * que abra muchas cuentas (cada SMS cuesta plata).
 *
 * Con IPv6 se usa ipKeyGenerator (agrupa por subred) — usar req.ip a secas dejaría
 * que un cliente IPv6 rote de dirección para saltarse el límite.
 */
import type { Request } from 'express';
import rateLimit, { ipKeyGenerator } from 'express-rate-limit';

const ipKey = (req: Request): string => `ip:${ipKeyGenerator(req.ip ?? '')}`;

/** Clave por usuario autenticado; sin sesión cae a la IP (no debería pasar: van tras authMiddleware). */
const userKey = (req: Request): string => {
  const userId = (req as Request & { user?: { userId?: string } }).user?.userId;
  return userId ? `u:${userId}` : ipKey(req);
};

/** 3 envíos de OTP por hora y por usuario — cada envío tiene costo (SMS/WhatsApp). */
export const phoneOtpSendLimiter = rateLimit({
  windowMs: 60 * 60 * 1000,
  limit: 3,
  keyGenerator: userKey,
  standardHeaders: true,
  legacyHeaders: false,
  message: { success: false, error: { code: 'TOO_MANY_REQUESTS', message: 'Demasiados envíos de código. Espera 1 hora.' } },
});

/** Techo por IP, holgado a propósito para redes compartidas (ver arriba). */
export const phoneOtpSendIpLimiter = rateLimit({
  windowMs: 60 * 60 * 1000,
  limit: 30,
  keyGenerator: ipKey,
  standardHeaders: true,
  legacyHeaders: false,
  message: { success: false, error: { code: 'TOO_MANY_REQUESTS', message: 'Demasiados envíos de código desde esta red. Espera 1 hora.' } },
});

/** 10 intentos de verificación por 15 min y por usuario — frena la fuerza bruta sobre el código de 6 dígitos. */
export const otpVerifyLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 10,
  keyGenerator: userKey,
  skipSuccessfulRequests: true,
  standardHeaders: true,
  legacyHeaders: false,
  message: { success: false, error: { code: 'TOO_MANY_REQUESTS', message: 'Demasiados intentos. Espera 15 minutos.' } },
});
