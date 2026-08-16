/**
 * Agente de chat de soporte — primera línea de atención al cliente/cuidador.
 * Responde con el conocimiento real del centro de ayuda (mismo contenido que
 * garden-app/lib/data/help_center_content.dart, condensado acá abajo — si
 * cambia una regla de negocio ahí, actualizar también esta copia).
 *
 * Nunca inventa una respuesta que no tiene: si la pregunta se sale de este
 * conocimiento, o el usuario necesita una decisión de verdad (no solo
 * información), marca necesitaHumano=true en vez de adivinar. Mismo
 * criterio que el resto de agentes del proyecto (ver documento-antecedentes.
 * agent.ts) — ante la duda, deriva, no decide.
 */
import { callClaude } from '../services/claude.service.js';
import { logAgentCall } from '../shared/agent-logger.js';
import logger from '../shared/logger.js';

const KNOWLEDGE_BASE = `
# RESERVAS Y CANCELACIONES
- Reservar: elegir servicio (Paseo/Hospedaje/Guardería) → filtrar cuidador → fecha y datos de la mascota → Meet & Greet obligatorio si es la primera reserva de Hospedaje/Guardería con ese cuidador → pagar (Billetera + QR) → esperar confirmación del cuidador.
- Cancelación Hospedaje/Guardería: >48h antes = 100% reembolso (menos Bs 10 de cargo administrativo); 24-48h = 50%; <24h o no-show = sin reembolso.
- Cancelación Paseo: >12h antes = 100%; 6-12h = 50%; <6h o no-show = sin reembolso.
- Reembolso a Billetera: inmediato. Reembolso a cuenta bancaria (QR): 1-3 días hábiles, lo procesa el equipo de Garden manualmente.
- Si cancela el cuidador con <24h: cliente recibe 100% siempre, y el cuidador recibe una penalización (3 cancelaciones tardías en 90 días = suspensión de 30 días).
- Meet & Greet: reunión gratuita de 20-30 min (presencial o videollamada), se coordina desde el chat de la reserva con botón "Proponer Meet & Greet". Cancelar después de un Meet & Greet ya realizado no da reembolso.

# PAGOS
- Comisión de plataforma: 10% sobre el precio del cuidador, la paga el cliente aparte. Si el cuidador cobra Bs 100, el cliente paga Bs 110; el cuidador recibe sus Bs 100 completos.
- El pago se libera al cuidador a las 24h de que ambas partes confirmen que el servicio terminó bien, o automático a las 72h si el cliente no confirma ni abre disputa.
- QR bancario: válido 15 minutos, se cancela solo si expira sin pago detectado. Verificación automática cada 5s tras tocar "Ya realicé el pago". Si el sistema de QR falla, existe "Solicitud de verificación manual" (subir comprobante).
- Billetera Garden: saldo interno, se acumula sobre todo por reembolsos. Se puede combinar con QR si no cubre el total.
- Donaciones a hogares de mascotas: voluntarias (Bs 5/10/20/personalizado hasta Bs 500), 0% comisión, 100% va al refugio.

# RETIROS (CUIDADORES)
- Configurar datos de cobro primero (Billetera → Datos de cobro): banco (ahorro/corriente + número de cuenta) o billetera digital (Tigo Money, Pago Fácil, etc. + número de celular). El nombre debe coincidir con el registrado en Garden.
- Retiro mínimo: Bs 50. No puede superar el saldo disponible (saldo total menos retiros ya pendientes). Tarda 1-3 días hábiles. Garden no cobra comisión por retirar.

# SER CUIDADOR
- Registro gratuito, wizard de varios pasos que guarda el progreso si cierras la app a la mitad. Requiere: mayor de 18 años, datos + dirección, foto de perfil, servicios y zona, precios (Bs 15-400 típico, rango por zona), disponibilidad, fotos (mín. 2, más fotos del espacio si ofrece Hospedaje/Guardería), bio + cuestionario, verificación de identidad (CI + prueba de vida con reconocimiento facial AWS Rekognition), verificación de teléfono y correo.
- Verificación de identidad: normalmente instantánea; si no se confirma automático, pasa a revisión manual (24-48h). Si falla, reintentar con buena luz, CI nítida y completa, rostro centrado sin lentes oscuros/gorra.
- Precio: lo fija el cuidador dentro del rango de su zona; es el monto íntegro que recibe (el 10% de comisión lo paga el cliente aparte). Cambiar el precio solo afecta reservas nuevas.

# DISPUTAS Y PROBLEMAS
- Se activa calificando con menos de 3 estrellas al finalizar un servicio — retiene el pago automáticamente y habilita "abrir disputa".
- El cuidador puede dar su versión; una vez que responde, un sistema de IA (Claude) analiza todo el historial y evidencia y da un veredicto: a favor del cuidador (libera el pago), a favor del cliente (reembolso completo), o parcial. El veredicto se graba en blockchain (Polygon) de forma inmutable.
- Apelación: 5 días hábiles desde el veredicto. La apelación la revisa una PERSONA real del equipo de Garden (no la IA), y esa decisión es la definitiva.
- Emergencia durante un servicio activo: el cuidador la reporta desde la pantalla del servicio; el tiempo se pausa automático, el equipo de Garden recibe alerta urgente, y se resuelve cuando el cuidador o un admin la marcan resuelta.

# CALIFICACIONES
- Aparece "Calificar experiencia" cuando el servicio se completa. 1-5 estrellas + comentario opcional. Menos de 3 estrellas retiene el pago y habilita disputa.

# CHAT Y SEGURIDAD
- Cada reserva tiene su propio chat en tiempo real, disponible desde el Meet & Greet hasta después del servicio (mientras no se haya calificado).
- Nunca coordinar pagos fuera de la app — va contra los Términos, pierde la protección del Fondo de Garantía Garden y la resolución de disputas, y puede suspender ambas cuentas permanentemente.

# CUENTA
- Eliminar cuenta: Perfil → Eliminar cuenta, con contraseña. Requiere no tener reservas activas/pendientes ni disputas abiertas. El saldo de Billetera se pierde (transferido a Garden) si no se retira antes. Los datos personales se anonimizan; el historial de transacciones/disputas se conserva por auditoría.
- Cambiar contraseña: Perfil → Configuración de cuenta → Cambiar contraseña (o "¿Olvidaste tu contraseña?" en el login).

# FONDO DE GARANTÍA
- Garden ofrece un fondo de garantía voluntario y discrecional para gastos veterinarios de emergencia derivados de un servicio (hasta Bs 2.000 aproximadamente), sujeto a revisión caso por caso — no es una póliza de seguro formal con una aseguradora. Cualquier reclamo sobre esto SIEMPRE necesita revisión humana, nunca lo resuelve el bot.
`.trim();

const SYSTEM_PROMPT = `
Eres el asistente de soporte de GARDEN, un marketplace de cuidado de mascotas en Santa Cruz de la Sierra, Bolivia (paseo, hospedaje y guardería). Le respondés en el chat a un cliente o cuidador que ya está usando la app.

Tu única fuente de verdad es esta base de conocimiento — nunca inventes montos, plazos o reglas que no estén acá:

${KNOWLEDGE_BASE}

Reglas:
1. Respondé en español boliviano, tono cercano y directo, sin tecnicismos innecesarios. Máximo 3-4 oraciones por respuesta.
2. Si la pregunta se responde con la base de conocimiento de arriba, contestala completa y con los datos reales (montos, plazos, nombres de botones).
3. Marca "necesitaHumano": true (y explicá brevemente por qué en "razon") cuando:
   - La pregunta no está cubierta por la base de conocimiento, o no estás seguro de la respuesta.
   - El usuario pide algo que requiere una decisión sobre SU caso puntual (revisar una disputa específica, aprobar un reembolso fuera de la política, un reclamo del fondo de garantía, algo con implicancia legal, o cualquier cosa donde adivinar podría perjudicarlo).
   - El usuario está claramente frustrado, enojado, o pide explícitamente hablar con una persona.
4. Ante la duda, preferí necesitaHumano=true a inventar o prometer algo que Garden no puede cumplir.
5. Si necesitaHumano es true, tu "respuesta" igual debe ser útil: reconocé lo que el usuario pidió, decí que un asesor humano va a revisar su caso, y si podés adelantar algo útil de la base de conocimiento mientras espera, hacelo.

Responde ÚNICAMENTE en JSON válido, sin texto adicional:
{
  "respuesta": "tu respuesta al usuario, en español, lista para mostrarse tal cual",
  "necesitaHumano": true o false,
  "razon": "solo si necesitaHumano es true: motivo breve para que el admin entienda de qué se trata sin releer todo el chat"
}
`.trim();

/** Temas donde SIEMPRE hace falta una persona, sin importar lo que el bot
 * crea poder resolver — dinero en disputa, baja de cuenta, reclamos del
 * fondo de garantía, o cualquier cosa con tinte legal. Chequeo determinístico
 * además del criterio del bot (defensa en profundidad, mismo espíritu que el
 * resto del proyecto no delega decisiones de plata 100% a la IA). */
const FORCED_ESCALATION_PATTERNS: Array<{ pattern: RegExp; razon: string }> = [
  { pattern: /\b(demanda|denuncia|abogad|legal|fiscal[ií]a|polic[ií]a)\b/i, razon: 'Menciona algo de índole legal/policial.' },
  { pattern: /\b(fondo de garant[ií]a|seguro veterinari|reclamo.*(veterinari|accidente)|accidente.*(mascota|perro|gato))\b/i, razon: 'Reclamo sobre el fondo de garantía / accidente con la mascota.' },
  { pattern: /\b(eliminar|borrar|cerrar|dar de baja).{0,15}\bcuenta\b/i, razon: 'Pide eliminar/dar de baja su cuenta.' },
  { pattern: /\b(estafa|me robaron|fraude|no me devolvieron|no me pagaron)\b/i, razon: 'Reclamo de dinero fuera de la política estándar.' },
  { pattern: /\bhablar con (una persona|un humano|alguien real|un asesor)\b/i, razon: 'Pidió explícitamente hablar con una persona.' },
];

export function requiereEscalacionForzada(message: string): string | null {
  for (const { pattern, razon } of FORCED_ESCALATION_PATTERNS) {
    if (pattern.test(message)) return razon;
  }
  return null;
}

export interface RespuestaSoporte {
  respuesta: string;
  necesitaHumano: boolean;
  razon?: string;
}

export interface MensajeHistorial {
  senderRole: 'CLIENT' | 'BOT' | 'ADMIN';
  message: string;
}

/** Arma un solo mensaje de usuario con el historial reciente + el mensaje
 * nuevo — callClaude no soporta multi-turno nativo, así que el historial va
 * como texto dentro del mismo user message. */
function buildUserMessage(historial: MensajeHistorial[], nuevoMensaje: string): string {
  const lines = historial.map((m) => {
    const who = m.senderRole === 'CLIENT' ? 'Usuario' : m.senderRole === 'BOT' ? 'Asistente' : 'Asesor humano';
    return `${who}: ${m.message}`;
  });
  lines.push(`Usuario: ${nuevoMensaje}`);
  return `Conversación hasta ahora:\n${lines.join('\n')}\n\nRespondé al último mensaje del Usuario.`;
}

export async function responderSoporte(params: {
  historial: MensajeHistorial[];
  nuevoMensaje: string;
  userId?: string;
}): Promise<RespuestaSoporte> {
  const { historial, nuevoMensaje, userId } = params;
  const start = Date.now();

  const forzada = requiereEscalacionForzada(nuevoMensaje);

  try {
    const userMessage = buildUserMessage(historial, nuevoMensaje);
    const resultado = await callClaude(SYSTEM_PROMPT, userMessage, 512) as RespuestaSoporte;

    if (typeof resultado?.respuesta !== 'string' || typeof resultado?.necesitaHumano !== 'boolean') {
      throw new Error('Respuesta sin campos respuesta/necesitaHumano válidos');
    }

    const necesitaHumano = resultado.necesitaHumano || forzada != null;
    const razon = forzada ?? resultado.razon;

    await logAgentCall({
      agentType: 'SOPORTE_CHAT',
      action: 'responder',
      input: { nuevoMensaje, historialLength: historial.length },
      output: { ...resultado, necesitaHumano, forzada },
      durationMs: Date.now() - start,
      status: 'SUCCESS',
      userId,
    });

    return { respuesta: resultado.respuesta, necesitaHumano, razon };
  } catch (err) {
    logger.error('[SoporteChat] Fallo técnico — se deriva a humano (no falla abierto)', {
      userId,
      error: err instanceof Error ? err.message : String(err),
    });
    await logAgentCall({
      agentType: 'SOPORTE_CHAT',
      action: 'responder',
      input: { nuevoMensaje, historialLength: historial.length },
      output: { error: err instanceof Error ? err.message : String(err) },
      durationMs: Date.now() - start,
      status: 'ERROR',
      userId,
    });
    // Fallo técnico (Claude caído, JSON inválido, etc.) — nunca dejar al
    // usuario sin respuesta ni fingir que el bot entendió: derivar siempre.
    return {
      respuesta: 'Ahora mismo no puedo darte una respuesta automática, pero ya avisé a un asesor humano para que te ayude en cuanto pueda.',
      necesitaHumano: true,
      razon: forzada ?? 'Fallo técnico del asistente automático.',
    };
  }
}
