/**
 * Entrega de códigos OTP (verificación de teléfono) — WhatsApp primero,
 * SMS como respaldo automático si WhatsApp falla o no está configurado.
 * Sin proveedor intermediario tipo Twilio.
 *
 * WhatsApp: WhatsApp Business Cloud API oficial de Meta. Requiere
 * WHATSAPP_PHONE_NUMBER_ID + WHATSAPP_ACCESS_TOKEN (env). Mientras no estén
 * configurados, se omite silenciosamente y se usa solo SMS.
 *
 * SMS: AWS End User Messaging SMS (sucesor de SNS/Pinpoint SMS clásico —
 * la cuenta de AWS ya está migrada a este servicio, la API clásica de SNS
 * Publish no usa el número de origen configurado en la consola). Reutiliza
 * las mismas credenciales AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY /
 * AWS_REGION ya usadas para Rekognition, más AWS_SMS_ORIGINATION_NUMBER
 * (el número Toll-Free configurado en la consola de AWS).
 */
import { PinpointSMSVoiceV2Client, SendTextMessageCommand } from '@aws-sdk/client-pinpoint-sms-voice-v2';
import { env } from '../config/env.js';
import logger from '../shared/logger.js';

export type OtpChannel = 'whatsapp' | 'sms' | 'none';

/** Normaliza a formato E.164 asumiendo Bolivia (+591) si no trae prefijo. */
function toE164Bolivia(phone: string): string {
  return phone.startsWith('+') ? phone : `+591${phone}`;
}

async function sendViaWhatsApp(toPhone: string, otp: string): Promise<boolean> {
  if (!env.WHATSAPP_PHONE_NUMBER_ID || !env.WHATSAPP_ACCESS_TOKEN) return false;

  try {
    const res = await fetch(
      `https://graph.facebook.com/v20.0/${env.WHATSAPP_PHONE_NUMBER_ID}/messages`,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${env.WHATSAPP_ACCESS_TOKEN}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          messaging_product: 'whatsapp',
          to: toPhone.replace('+', ''),
          type: 'template',
          template: {
            name: env.WHATSAPP_AUTH_TEMPLATE_NAME,
            language: { code: 'es' },
            components: [
              { type: 'body', parameters: [{ type: 'text', text: otp }] },
              {
                type: 'button',
                sub_type: 'url',
                index: '0',
                parameters: [{ type: 'text', text: otp }],
              },
            ],
          },
        }),
      }
    );

    if (!res.ok) {
      const body = await res.text().catch(() => '');
      logger.warn(`WhatsApp OTP send failed (${res.status}): ${body.slice(0, 300)}`);
      return false;
    }
    return true;
  } catch (err) {
    logger.error(String(err), 'WhatsApp OTP send error — falling back to SMS');
    return false;
  }
}

async function sendViaSms(toPhone: string, otp: string): Promise<boolean> {
  if (!env.AWS_ACCESS_KEY_ID || !env.AWS_SECRET_ACCESS_KEY || !env.AWS_SMS_ORIGINATION_NUMBER) {
    logger.warn('AWS End User Messaging SMS not configured — OTP code saved in DB only (manual support)');
    return false;
  }
  try {
    const client = new PinpointSMSVoiceV2Client({
      region: env.AWS_REGION,
      credentials: { accessKeyId: env.AWS_ACCESS_KEY_ID, secretAccessKey: env.AWS_SECRET_ACCESS_KEY },
    });
    await client.send(
      new SendTextMessageCommand({
        DestinationPhoneNumber: toPhone,
        OriginationIdentity: env.AWS_SMS_ORIGINATION_NUMBER,
        MessageBody: `GARDEN: tu código de verificación es ${otp}. Vence en 10 minutos. No lo compartas con nadie.`,
        MessageType: 'TRANSACTIONAL',
      })
    );
    return true;
  } catch (err) {
    logger.error(String(err), 'AWS End User Messaging SMS send error — code saved in DB for manual support');
    return false;
  }
}

/**
 * Envía el código OTP intentando WhatsApp primero y SMS como respaldo.
 * Devuelve el canal que realmente entregó el mensaje ('none' si ambos
 * fallaron o no hay proveedor configurado — el código sigue válido en BD
 * para que soporte lo entregue manualmente si hace falta).
 */
export async function sendOtp(phone: string, otp: string): Promise<OtpChannel> {
  const toPhone = toE164Bolivia(phone);

  if (await sendViaWhatsApp(toPhone, otp)) return 'whatsapp';
  if (await sendViaSms(toPhone, otp)) return 'sms';
  return 'none';
}
