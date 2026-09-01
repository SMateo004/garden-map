/**
 * Entrega de códigos OTP (verificación de teléfono) — WhatsApp primero,
 * SMS como respaldo automático si WhatsApp falla o no está configurado.
 *
 * WhatsApp: WhatsApp Business Cloud API oficial de Meta. Requiere
 * WHATSAPP_PHONE_NUMBER_ID + WHATSAPP_ACCESS_TOKEN (env). Mientras no estén
 * configurados, se omite silenciosamente y se usa solo SMS.
 *
 * SMS: dos proveedores en cadena.
 *   1. Vonage (SMS API clásica, rest.nexmo.com) — no requiere número
 *      Toll-Free ni Business Verification tipo AWS End User Messaging (el
 *      que se usaba antes, descartado por eso: rechazo repetido de
 *      "Business Verification Failed" sin forma de reintentarlo sin
 *      entidad legal en EEUU). Reemplazó a Infobip (cuenta trabada
 *      semanas sin respuesta de ventas, agosto 2026). Mientras no tenga
 *      VONAGE_API_KEY/VONAGE_API_SECRET configurados, se omite. El Sender
 *      ID alfanumérico (SMS_SENDER_ID) requiere registro aparte ante Tigo
 *      para no filtrarse en silencio — Entel lo reemplaza por un shortcode
 *      fijo igual (no es un bug), Viva no tiene restricciones.
 *   2. AWS SNS Publish (API clásica, distinta de End User Messaging SMS)
 *      — reutiliza AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY/AWS_REGION ya
 *      configurados para Rekognition. No requiere número dedicado ni
 *      Business Verification: si no se especifica origen, AWS elige uno
 *      del pool compartido. Sirve de red de contención si Vonage falla —
 *      entrega menos confiable que una ruta directa paga, pero funciona
 *      sin trámite adicional.
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

async function sendViaVonage(toPhone: string, otp: string): Promise<boolean> {
  if (!env.VONAGE_API_KEY || !env.VONAGE_API_SECRET) return false;
  try {
    const res = await fetch('https://rest.nexmo.com/sms/json', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        api_key: env.VONAGE_API_KEY,
        api_secret: env.VONAGE_API_SECRET,
        to: toPhone.replace('+', ''),
        from: env.SMS_SENDER_ID,
        text: `GARDEN: tu código de verificación es ${otp}. Vence en 10 minutos. No lo compartas con nadie.`,
      }),
    });

    if (!res.ok) {
      const body = await res.text().catch(() => '');
      logger.error(`Vonage SMS send failed (${res.status}): ${body.slice(0, 300)}`);
      return false;
    }

    // La SMS API clásica de Vonage responde 200 aunque el envío falle — el
    // resultado real viene en messages[0].status ("0" = ok, cualquier otro
    // valor es un código de error, ver developer.vonage.com/en/api/sms).
    const data = (await res.json()) as { messages?: Array<{ status?: string; 'error-text'?: string }> };
    const first = data.messages?.[0];
    if (first?.status !== '0') {
      logger.error(`Vonage SMS send rejected (status ${first?.status}): ${first?.['error-text'] ?? 'sin detalle'}`);
      return false;
    }
    return true;
  } catch (err) {
    logger.error(String(err), 'Vonage SMS send error — falling back to AWS SNS');
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
 * Envía el código OTP: WhatsApp primero, después Vonage, después AWS SNS
 * como última red de contención. Devuelve el canal que realmente entregó
 * el mensaje ('none' si los tres fallaron o no hay ninguno configurado —
 * el código sigue válido en BD para que soporte lo entregue manualmente).
 */
export async function sendOtp(phone: string, otp: string): Promise<OtpChannel> {
  const toPhone = toE164Bolivia(phone);

  if (await sendViaWhatsApp(toPhone, otp)) return 'whatsapp';
  if (await sendViaVonage(toPhone, otp)) return 'sms';
  if (await sendViaAwsSns(toPhone, otp)) return 'sms';
  return 'none';
}
