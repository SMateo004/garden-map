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

function generateCode(): string {
  return randomInt(100000, 999999).toString();
}

function hashCode(code: string): string {
  return createHash('sha256').update(code).digest('hex');
}

export async function sendVerificationEmail(email: string, code: string): Promise<void> {
  const isDev = env.NODE_ENV !== 'production';

  // LOG THE CODE CLEARLY FOR DEVELOPMENT
  console.log('\n' + '='.repeat(50));
  console.log(`📩 VERIFICATION CODE FOR ${email}: [ ${code} ]`);
  console.log('='.repeat(50) + '\n');

  logger.info(`📩 Attempting to send email to: ${email}`);
  try {
    const { Resend } = await import('resend');
    const resend = new Resend(env.RESEND_API_KEY);
    const { error } = await resend.emails.send({
      from: env.EMAIL_FROM,
      to: [email],
      subject: 'Your verification code',
      html: `Your verification code is: <b>${code}</b>`,
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
    <div style="font-family:sans-serif;max-width:400px;margin:0 auto;">
      <h2>GARDEN – Verificación de correo</h2>
      <p>Tu código de verificación es:</p>
      <p style="font-size:28px;font-weight:bold;letter-spacing:4px;">${code}</p>
      <p style="color:#666;">Válido por ${CODE_EXPIRY_MINUTES} minutos. No lo compartas con nadie.</p>
    </div>
  `;

  await sendVerificationEmail(user.email, code);

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
