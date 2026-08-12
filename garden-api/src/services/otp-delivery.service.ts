/**
 * Entrega de códigos OTP (verificación de teléfono) — WhatsApp primero,
 * SMS como respaldo automático si WhatsApp falla o no está configurado.
 *
 * WhatsApp: WhatsApp Business Cloud API oficial de Meta. Requiere
 * WHATSAPP_PHONE_NUMBER_ID + WHATSAPP_ACCESS_TOKEN (env). Mientras no estén
 * configurados, se omite silenciosamente y se usa solo SMS.
 *
 * SMS: dos proveedores en cadena.
 *   1. Infobip — conexiones directas con operadoras en Bolivia
 *      (Entel/Tigo/Viva), no requiere número Toll-Free ni Business
 *      Verification tipo AWS End User Messaging (el que se usaba antes,
 *      descartado por eso: rechazo repetido de "Business Verification
 *      Failed" sin forma de reintentarlo sin entidad legal en EEUU).
 *      Cuenta en proceso de alta (agosto 2026) — mientras no tenga
 *      INFOBIP_API_KEY/INFOBIP_BASE_URL configurados, se omite.
 *   2. AWS SNS Publish (API clásica, distinta de End User Messaging SMS)
 *      — reutiliza AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY/AWS_REGION ya
 *      configurados para Rekognition. No requiere número dedicado ni
 *      Business Verification: si no se especifica origen, AWS elige uno
 *      del pool compartido. Sirve de red de contención mientras Infobip
 *      termina su alta — entrega menos confiable que una ruta directa
 *      paga, pero funciona sin trámite adicional.
 */
import { PublishCommand, SNSClient } from '@aws-sdk/client-sns';
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
                sub_type: 'copy_code',
                index: '0',
                parameters: [{ type: 'coupon_code', coupon_code: otp }],
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

async function sendViaInfobip(toPhone: string, otp: string): Promise<boolean> {
  if (!env.INFOBIP_API_KEY || !env.INFOBIP_BASE_URL) return false;
  try {
    const res = await fetch(`https://${env.INFOBIP_BASE_URL}/sms/2/text/advanced`, {
      method: 'POST',
      headers: {
        Authorization: `App ${env.INFOBIP_API_KEY}`,
        'Content-Type': 'application/json',
        Accept: 'application/json',
      },
      body: JSON.stringify({
        messages: [
          {
            from: env.SMS_SENDER_ID,
            destinations: [{ to: toPhone.replace('+', '') }],
            text: `GARDEN: tu código de verificación es ${otp}. Vence en 10 minutos. No lo compartas con nadie.`,
          },
        ],
      }),
    });

    if (!res.ok) {
      const body = await res.text().catch(() => '');
      logger.error(`Infobip SMS send failed (${res.status}): ${body.slice(0, 300)}`);
      return false;
    }
    return true;
  } catch (err) {
    logger.error(String(err), 'Infobip SMS send error — falling back to AWS SNS');
    return false;
  }
}

async function sendViaAwsSns(toPhone: string, otp: string): Promise<boolean> {
  if (!env.AWS_ACCESS_KEY_ID || !env.AWS_SECRET_ACCESS_KEY) return false;
  try {
    const client = new SNSClient({
      region: env.AWS_REGION,
      credentials: { accessKeyId: env.AWS_ACCESS_KEY_ID, secretAccessKey: env.AWS_SECRET_ACCESS_KEY },
    });
    await client.send(
      new PublishCommand({
        PhoneNumber: toPhone,
        Message: `GARDEN: tu código de verificación es ${otp}. Vence en 10 minutos. No lo compartas con nadie.`,
        MessageAttributes: {
          'AWS.SNS.SMS.SMSType': { DataType: 'String', StringValue: 'Transactional' },
          'AWS.SNS.SMS.SenderID': { DataType: 'String', StringValue: env.SMS_SENDER_ID },
        },
      })
    );
    return true;
  } catch (err) {
    logger.error(String(err), 'AWS SNS Publish error — code saved in DB for manual support');
    return false;
  }
}

/**
 * Envía el código OTP: WhatsApp primero, después Infobip, después AWS SNS
 * como última red de contención. Devuelve el canal que realmente entregó
 * el mensaje ('none' si los tres fallaron o no hay ninguno configurado —
 * el código sigue válido en BD para que soporte lo entregue manualmente).
 */
export async function sendOtp(phone: string, otp: string): Promise<OtpChannel> {
  const toPhone = toE164Bolivia(phone);

  if (await sendViaWhatsApp(toPhone, otp)) return 'whatsapp';
  if (await sendViaInfobip(toPhone, otp)) return 'sms';
  if (await sendViaAwsSns(toPhone, otp)) return 'sms';
  return 'none';
}
