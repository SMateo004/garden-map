/**
 * Password reset flow:
 *  1. requestPasswordReset(email)  → generates secure token, stores hash, sends email.
 *  2. validateResetToken(token)    → returns userId if token is valid & unused.
 *  3. resetPassword(token, pass)   → validates token, updates password, invalidates all sessions.
 *
 * Security:
 *  - Token: 32 random bytes → hex (64-char) → stored as SHA-256 hash (prevent DB leak).
 *  - Expiry: 1 hour.
 *  - Single use: marked usedAt on success.
 *  - All sessions (RefreshTokens) revoked on reset.
 *  - Same HTTP response for valid/invalid email (prevent enumeration).
 *  - Rate-limited at route level (3 requests/15 min per IP).
 */

import { randomBytes, createHash } from 'crypto';
import prisma from '../../config/database.js';
import { env } from '../../config/env.js';
import { BadRequestError, NotFoundError } from '../../shared/errors.js';
import logger from '../../shared/logger.js';
import { sendVerificationEmail } from './email.service.js';
import bcrypt from 'bcrypt';

const TOKEN_EXPIRY_MINUTES = 60;
const MIN_PASSWORD_LENGTH = 8;

function generateToken(): string {
  return randomBytes(32).toString('hex'); // 64-char hex
}

function hashToken(token: string): string {
  return createHash('sha256').update(token).digest('hex');
}

/**
 * Step 1 — Request password reset.
 * Always returns the same success response to prevent user enumeration.
 */
export async function requestPasswordReset(email: string): Promise<void> {
  const normalizedEmail = email.trim().toLowerCase();

  const user = await prisma.user.findFirst({
    where: { email: normalizedEmail, isDeleted: false },
    select: { id: true, firstName: true, email: true },
  });

  if (!user) {
    // Intentional: same response whether email exists or not.
    logger.info(`Password reset requested for non-existent email: ${normalizedEmail}`);
    return;
  }

  // Rate-limit: delete any existing unused, non-expired token for this user
  // (only allow 1 active token at a time, but keep used ones for audit).
  await prisma.passwordReset.deleteMany({
    where: { userId: user.id, usedAt: null, expiresAt: { gt: new Date() } },
  });

  const rawToken = generateToken();
  const tokenHash = hashToken(rawToken);
  const expiresAt = new Date(Date.now() + TOKEN_EXPIRY_MINUTES * 60 * 1000);

  await prisma.passwordReset.create({
    data: { userId: user.id, tokenHash, expiresAt },
  });

  // Build reset URL
  const baseUrl = env.FRONTEND_URL ?? 'https://garden-map.vercel.app';
  const resetUrl = `${baseUrl}/reset-password?token=${rawToken}`;

  logger.info(`Password reset token for ${normalizedEmail}: [REDACTED — check email]`);

  const html = buildResetEmail(user.firstName, resetUrl, TOKEN_EXPIRY_MINUTES);
  await sendVerificationEmail(normalizedEmail, '(reset)', html);
}

/**
 * Step 2 — Validate token (used by frontend to check token before showing form).
 */
export async function validateResetToken(rawToken: string): Promise<{ userId: string; email: string }> {
  const tokenHash = hashToken(rawToken.trim());

  const record = await prisma.passwordReset.findUnique({
    where: { tokenHash },
    include: { user: { select: { id: true, email: true, isDeleted: true } } },
  });

  if (!record) throw new BadRequestError('El enlace de recuperación no es válido.', 'INVALID_RESET_TOKEN');
  if (record.usedAt) throw new BadRequestError('Este enlace ya fue utilizado. Solicita uno nuevo.', 'TOKEN_ALREADY_USED');
  if (record.expiresAt < new Date()) throw new BadRequestError('El enlace ha expirado. Solicita uno nuevo.', 'RESET_TOKEN_EXPIRED');
  if (record.user.isDeleted) throw new BadRequestError('La cuenta no existe.', 'ACCOUNT_NOT_FOUND');

  return { userId: record.user.id, email: record.user.email };
}

/**
 * Step 3 — Reset the password.
 */
export async function resetPassword(rawToken: string, newPassword: string): Promise<void> {
  // Validate
  if (!newPassword || newPassword.length < MIN_PASSWORD_LENGTH) {
    throw new BadRequestError(
      `La contraseña debe tener al menos ${MIN_PASSWORD_LENGTH} caracteres.`,
      'PASSWORD_TOO_SHORT'
    );
  }

  const tokenHash = hashToken(rawToken.trim());

  const record = await prisma.passwordReset.findUnique({
    where: { tokenHash },
    include: { user: { select: { id: true, email: true, isDeleted: true, passwordHash: true } } },
  });

  if (!record) throw new BadRequestError('El enlace de recuperación no es válido.', 'INVALID_RESET_TOKEN');
  if (record.usedAt) throw new BadRequestError('Este enlace ya fue utilizado. Solicita uno nuevo.', 'TOKEN_ALREADY_USED');
  if (record.expiresAt < new Date()) throw new BadRequestError('El enlace ha expirado. Solicita uno nuevo.', 'RESET_TOKEN_EXPIRED');
  if (record.user.isDeleted) throw new BadRequestError('La cuenta no existe.', 'ACCOUNT_NOT_FOUND');

  // Prevent using the same password as current (security best practice)
  const isSamePassword = await bcrypt.compare(newPassword, record.user.passwordHash);
  if (isSamePassword) {
    throw new BadRequestError('La nueva contraseña no puede ser igual a la actual.', 'SAME_PASSWORD');
  }

  const passwordHash = await bcrypt.hash(newPassword, 12);

  await prisma.$transaction([
    // Mark token as used
    prisma.passwordReset.update({
      where: { id: record.id },
      data: { usedAt: new Date() },
    }),
    // Update password
    prisma.user.update({
      where: { id: record.user.id },
      data: { passwordHash },
    }),
    // Revoke ALL refresh tokens (force re-login everywhere)
    prisma.refreshToken.updateMany({
      where: { userId: record.user.id, revokedAt: null },
      data: { revokedAt: new Date() },
    }),
  ]);

  logger.info(`Password reset completed for userId=${record.user.id}`);
}

// ── Email template ───────────────────────────────────────────────────────────

function buildResetEmail(firstName: string, resetUrl: string, expiryMinutes: number): string {
  const expiryText = expiryMinutes >= 60
    ? `${expiryMinutes / 60} hora${expiryMinutes / 60 !== 1 ? 's' : ''}`
    : `${expiryMinutes} minutos`;

  return `
<div style="font-family:sans-serif;max-width:520px;margin:0 auto;background:#fff;border-radius:16px;overflow:hidden;box-shadow:0 2px 12px rgba(0,0,0,.08);">
  <div style="background:#16a34a;padding:28px 32px;text-align:center;">
    <h1 style="color:#fff;margin:0;font-size:24px;font-weight:900;letter-spacing:1px;">🌿 GARDEN</h1>
    <p style="color:#bbf7d0;margin:6px 0 0;font-size:13px;">Cuidadores de confianza</p>
  </div>
  <div style="padding:32px;">
    <h2 style="margin:0 0 8px;font-size:18px;color:#111;">Hola ${firstName}, restablece tu contraseña</h2>
    <p style="color:#555;font-size:14px;margin:0 0 24px;">
      Recibimos una solicitud para restablecer la contraseña de tu cuenta GARDEN.
      Haz clic en el botón de abajo para crear una nueva contraseña.
      El enlace es válido por <strong>${expiryText}</strong>.
    </p>
    <div style="text-align:center;margin:0 0 24px;">
      <a href="${resetUrl}"
         style="display:inline-block;background:#16a34a;color:#fff;font-weight:700;font-size:15px;text-decoration:none;padding:14px 32px;border-radius:12px;box-shadow:0 4px 12px rgba(22,163,74,.3);">
        Restablecer contraseña
      </a>
    </div>
    <p style="color:#999;font-size:12px;margin:0 0 8px;">
      Si no puedes hacer clic en el botón, copia y pega este enlace en tu navegador:
    </p>
    <p style="color:#16a34a;font-size:12px;word-break:break-all;margin:0 0 16px;">${resetUrl}</p>
    <hr style="border:none;border-top:1px solid #f0f0f0;margin:16px 0;" />
    <p style="color:#999;font-size:11px;margin:0;">
      Si no solicitaste restablecer tu contraseña, ignora este mensaje. Tu cuenta está segura.
      Nunca compartas este enlace con nadie.
    </p>
  </div>
</div>`;
}
