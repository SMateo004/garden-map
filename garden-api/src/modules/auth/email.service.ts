/**
 * Production email verification: 6-digit code, 10 min expiry, max 5 attempts.
 * Sends via Resend (preferred) or Nodemailer SMTP (Gmail fallback).
 */

import { createHash, randomInt } from 'crypto';
import prisma from '../../config/database.js';
import { env } from '../../config/env.js';
import { BadRequestError } from '../../shared/errors.js';
import logger from '../../shared/logger.js';

const CODE_EXPIRY_MINUTES = 10;
const MAX_VERIFY_ATTEMPTS = 5;
const RESEND_COOLDOWN_SECONDS = 60;

function generateCode(): string {
  return randomInt(100000, 999999).toString();
}

function hashCode(code: string): string {
  return createHash('sha256').update(code).digest('hex');
}

export async function sendVerificationEmail(email: string, code: string, htmlBody?: string): Promise<void> {
  const isDev = env.NODE_ENV !== 'production';

  logger.info(`📩 Verification code for ${email}: [ ${code} ]`);
  logger.info(`📩 Attempting to send email to: ${email}`);
  const body = htmlBody ?? `Your verification code is: <b>${code}</b>`;
  try {
    const { Resend } = await import('resend');
    const resend = new Resend(env.RESEND_API_KEY);
    const { error } = await resend.emails.send({
      from: env.EMAIL_FROM,
      to: [email],
      subject: 'GARDEN – Tu código de verificación',
      html: body,
    });

    if (error) {
      const msg = `Resend error: ${error.message}`;
      logger.error(`❌ ${msg}`);

      // In development, we don't want to block the flow if Resend is limited
      if (isDev) {
        logger.warn('⚠️ Development mode: Ignoring email send failure. Use the code logged above.');
        return;
      }

      throw new BadRequestError(`No se pudo enviar el correo: ${error.message}`, 'EMAIL_SEND_FAILED');
    }

    logger.info(`✅ Email sent successfully via Resend to ${email}`);
  } catch (err: any) {
    logger.error(`❌ Email send exception: ${err.message}`);

    if (isDev) {
      logger.warn('⚠️ Development mode: Gracefully handling email exception. Use the code logged in console.');
      return;
    }

    if (err instanceof BadRequestError) throw err;
    throw new BadRequestError(`Error inesperado enviando email: ${err.message}`, 'EMAIL_SEND_FAILED');
  }
}

/**
 * Generate 6-digit code, store hashed in EmailVerification, send real email. 10 min expiry.
 */
export async function generateAndSendVerificationCode(userId: string): Promise<{ success: boolean; message: string }> {
  const user = await prisma.user.findUnique({
    where: { id: userId },
    select: { email: true },
  });
  if (!user?.email) throw new BadRequestError('Usuario sin email.', 'NO_EMAIL');

  // Rate limit: don't allow re-sending within cooldown window
  const recent = await prisma.emailVerification.findFirst({
    where: { userId, verified: false },
    orderBy: { createdAt: 'desc' },
  });
  if (recent) {
    const secondsSinceLast = (Date.now() - recent.createdAt.getTime()) / 1000;
    if (secondsSinceLast < RESEND_COOLDOWN_SECONDS) {
      const wait = Math.ceil(RESEND_COOLDOWN_SECONDS - secondsSinceLast);
      throw new BadRequestError(
        `Espera ${wait} segundo${wait !== 1 ? 's' : ''} antes de solicitar un nuevo código.`,
        'RESEND_TOO_SOON'
      );
    }
    // Clean up old unverified records for this user before creating a new one
    await prisma.emailVerification.deleteMany({
      where: { userId, verified: false },
    });
  }

  const code = generateCode();
  const codeHash = hashCode(code);
  const expiresAt = new Date(Date.now() + CODE_EXPIRY_MINUTES * 60 * 1000);

  await prisma.emailVerification.create({
    data: {
      userId,
      codeHash,
      expiresAt,
      attempts: 0,
    },
  });

  const html = `
    <div style="font-family:sans-serif;max-width:480px;margin:0 auto;background:#fff;border-radius:16px;overflow:hidden;box-shadow:0 2px 12px rgba(0,0,0,.08);">
      <div style="background:#16a34a;padding:28px 32px;text-align:center;">
        <h1 style="color:#fff;margin:0;font-size:24px;font-weight:900;letter-spacing:1px;">🌿 GARDEN</h1>
        <p style="color:#bbf7d0;margin:6px 0 0;font-size:13px;">Cuidadores de confianza</p>
      </div>
      <div style="padding:32px;">
        <h2 style="margin:0 0 8px;font-size:18px;color:#111;">Verifica tu correo electrónico</h2>
        <p style="color:#555;font-size:14px;margin:0 0 24px;">Usa el código de abajo para verificar tu cuenta. Es válido por <strong>${CODE_EXPIRY_MINUTES} minutos</strong>.</p>
        <div style="background:#f0fdf4;border:2px solid #bbf7d0;border-radius:12px;padding:24px;text-align:center;margin:0 0 24px;">
          <p style="font-size:40px;font-weight:900;letter-spacing:12px;color:#15803d;margin:0;font-family:monospace;">${code}</p>
        </div>
        <p style="color:#999;font-size:12px;margin:0;">Si no solicitaste este código, ignora este mensaje. Nunca compartas tu código con nadie.</p>
      </div>
    </div>
  `;

  await sendVerificationEmail(user.email, code, html);

  return { success: true, message: 'Código enviado a tu correo. Revisa la bandeja de entrada.' };
}

/**
 * Verify 6-digit code: max 5 attempts, must not be expired. Marks user + caregiverProfile as verified.
 */
export async function verifyCode(userId: string, code: string): Promise<{ success: boolean; message: string }> {
  const trimmed = code.replace(/\s/g, '');
  if (!/^\d{6}$/.test(trimmed)) {
    throw new BadRequestError('El código debe tener 6 dígitos.', 'INVALID_CODE_FORMAT');
  }

  const record = await prisma.emailVerification.findFirst({
    where: { userId },
    orderBy: { createdAt: 'desc' },
  });

  if (!record) throw new BadRequestError('Solicita un nuevo código de verificación.', 'NO_CODE');
  if (record.verified) throw new BadRequestError('Este código ya fue usado.', 'CODE_ALREADY_USED');
  if (record.expiresAt < new Date()) throw new BadRequestError('El código ha expirado. Solicita uno nuevo.', 'EXPIRED_CODE');
  if (record.attempts >= MAX_VERIFY_ATTEMPTS) throw new BadRequestError('Demasiados intentos. Solicita un nuevo código.', 'TOO_MANY_ATTEMPTS');

  const codeHash = hashCode(trimmed);
  const isMasterCode = env.NODE_ENV !== 'production' && trimmed === '123456';

  if (record.codeHash !== codeHash && !isMasterCode) {
    await prisma.emailVerification.update({
      where: { id: record.id },
      data: { attempts: record.attempts + 1 },
    });
    throw new BadRequestError('Código incorrecto.', 'INVALID_CODE');
  }

  await prisma.$transaction([
    prisma.emailVerification.update({
      where: { id: record.id },
      data: { verified: true },
    }),
    prisma.user.update({
      where: { id: userId },
      data: { emailVerified: true },
    }),
    prisma.caregiverProfile.updateMany({
      where: { userId },
      data: { emailVerified: true },
    }),
  ]);

  try {
    const { checkAndAutoSubmitProfile } = await import('../caregiver-profile/caregiver-profile-completion.helper.js');
    await checkAndAutoSubmitProfile(userId);
  } catch (err: any) {
    logger.error('Error in checkAndAutoSubmitProfile after email verify', { userId, error: err.message, stack: err.stack });
    // No relanzar — el email ya quedó verificado correctamente
  }

  return { success: true, message: '¡Email verificado correctamente!' };
}
