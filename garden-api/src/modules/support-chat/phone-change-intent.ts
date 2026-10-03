/**
 * "Quiero cambiar mi teléfono" en el chat de soporte — manejado SIN pasar por el
 * modelo de lenguaje. Autorizar un cambio de número es una decisión sobre la
 * cuenta (un teléfono verificado es el canal de contacto), así que la detección
 * es un patrón fijo y la autorización la hace el servicio con reglas fijas
 * (ver auth/phone-change.service.ts). El texto del usuario nunca decide nada
 * más allá de "mencionó el tema": no hay forma de convencer al bot de abrir la
 * ventana para otra cuenta, porque siempre actúa sobre el dueño del hilo.
 */
import { authorizePhoneChange, PHONE_CHANGE_WINDOW_MINUTES } from '../auth/phone-change.service.js';
import type { RespuestaSoporte } from '../../agents/soporte-chat.agent.js';

const VERBO = '(?:cambi|actualiz|modific|edit|corregi|corrig|reemplaz|poner|pon[ée]r)\\w*';
const OBJETO = '(?:n[uú]mero|tel[eé]fono|celular|cel)\\b';

// "cambiar mi número", "quiero actualizar el teléfono", "mi celular ya no es el mismo, cámbienlo"
const PATRON_CAMBIO = new RegExp(`\\b${VERBO}.{0,40}\\b${OBJETO}|\\b${OBJETO}.{0,40}\\b${VERBO}`, 'iu');
// Otros "números" y teléfonos ajenos que NO son el de la propia cuenta.
const PATRON_EXCLUIDO = /n[uú]mero de (cuenta|ci|carnet|nit|reserva|tarjeta|pedido|factura|comprobante)|(tel[eé]fono|n[uú]mero|celular) (del|de la|de el) (cuidador|cuidadora|due[ñn]o|due[ñn]a|cliente|refugio|veterinari\w*)|contacto de emergencia/iu;

export function detectaCambioDeTelefono(message: string): boolean {
  return PATRON_CAMBIO.test(message) && !PATRON_EXCLUIDO.test(message);
}

export async function responderCambioDeTelefono(userId: string): Promise<RespuestaSoporte> {
  const result = await authorizePhoneChange(userId);

  switch (result.status) {
    case 'AUTHORIZED':
    case 'ALREADY_AUTHORIZED':
      return {
        respuesta:
          `Listo, autoricé el cambio de tu número. Tienes ${PHONE_CHANGE_WINDOW_MINUTES} minutos: entra a Perfil → Mis Datos, ` +
          'escribe tu número nuevo y te mandaremos un código por SMS a ESE número para confirmarlo. ' +
          'Si no lo confirmas, se mantiene tu número actual. También te avisamos por correo.',
        necesitaHumano: false,
      };
    case 'NOT_VERIFIED':
      return {
        respuesta:
          'Tu número todavía no está verificado, así que puedes corregirlo tú mismo en Perfil → Mis Datos ' +
          'y luego verificarlo con el código que te enviamos por SMS. No hace falta que lo autoricemos.',
        necesitaHumano: false,
      };
    case 'RATE_LIMITED':
      return {
        respuesta:
          'Ya autorizamos un cambio de número en las últimas 24 horas. Para hacer otro cambio, ' +
          'un asesor del equipo tiene que revisarlo — ya le avisé y te responderá por acá.',
        necesitaHumano: true,
        razon: 'Pidió cambiar su teléfono verificado por tercera vez en 24h (límite del bot).',
      };
  }
}
