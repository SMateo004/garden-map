/**
 * Agente de Validación de Fotos — evita que dueños/cuidadores suban una foto
 * que no corresponde a lo pedido (ej. un meme en vez de una foto de mascota,
 * una foto random en vez del rostro de perfil, o una captura de pantalla en
 * vez del espacio real donde se cuidará a la mascota).
 *
 * Sigue el mismo patrón que el Agente de Precios (precios.agent.ts): usa
 * callClaude (aquí, su variante con visión) y registra cada llamada en
 * AgentLog para que aparezca en el Monitor de Agentes del panel admin —
 * a diferencia de PRECIO/CALIFICACION, este SÍ loguea explícitamente
 * (ver nota en admin.controller.ts sobre la inconsistencia existente).
 */
import { callClaudeVision } from '../services/claude.service.js';
import { logAgentCall } from '../shared/agent-logger.js';
import logger from '../shared/logger.js';

export type CategoriaFoto = 'ROSTRO_HUMANO' | 'MASCOTA' | 'ESPACIO_HOGAR';

const DESCRIPCION_CATEGORIA: Record<CategoriaFoto, string> = {
  ROSTRO_HUMANO: 'una foto de perfil que muestre claramente el rostro de una persona real (no un dibujo, logo, mascota, paisaje ni pantalla de otro dispositivo)',
  MASCOTA: 'una foto real de un animal/mascota (perro, gato, u otra mascota doméstica) — no un dibujo, meme, ni una foto sin ningún animal visible',
  ESPACIO_HOGAR: 'una foto real de un espacio de un hogar (living, patio, jardín, dormitorio, zona de comida, etc.) donde se cuidaría a una mascota — no una foto de una persona, un documento, o una imagen sin relación a un espacio habitable',
};

const SYSTEM_PROMPT_FOTOS = `
Eres el Agente de Validación de Fotos de GARDEN, una plataforma de cuidado
de mascotas en Santa Cruz de la Sierra, Bolivia.

Tu única función es revisar si una foto subida por un usuario corresponde
a lo que la app le pidió — nada más. No evalúas calidad artística, ni
iluminación perfecta, solo si el contenido corresponde a la categoría pedida.

Sé razonable: acepta fotos imperfectas (mal encuadre, algo de desenfoque,
ángulos raros) siempre que el contenido esperado SÍ esté presente y sea
reconocible. Rechaza solo cuando el contenido pedido claramente NO está,
o cuando parece una foto genérica/random sin relación (capturas de pantalla,
memes, fotos de otra cosa completamente distinta, imágenes en blanco/negras).

Responde ÚNICAMENTE en formato JSON válido, sin texto adicional:
{
  "valida": true o false,
  "razon": "máximo 1 oración simple y amigable en español, explicando por qué se aceptó o rechazó (para mostrársela directo al usuario)"
}
`;

export interface ResultadoValidacionFoto {
  valida: boolean;
  razon: string;
}

/**
 * Valida que una foto corresponda a la categoría esperada.
 * Nunca lanza por un rechazo del contenido (eso es un resultado válido,
 * `valida: false`) — solo lanza si la llamada a Claude falla técnicamente
 * (red, parseo, etc.), y el caller decide si eso bloquea o deja pasar.
 */
export async function validarFoto(params: {
  imageBuffer: Buffer;
  mediaType: 'image/jpeg' | 'image/png' | 'image/webp' | 'image/gif';
  categoria: CategoriaFoto;
  userId?: string;
  contexto?: string; // ej. "foto de perfil de cuidador", para logging
}): Promise<ResultadoValidacionFoto> {
  const { imageBuffer, mediaType, categoria, userId, contexto } = params;
  const start = Date.now();

  const mensaje = `Esta foto debe ser: ${DESCRIPCION_CATEGORIA[categoria]}.\n\n¿Corresponde? Responde con el JSON pedido.`;

  try {
    const resultado = await callClaudeVision(SYSTEM_PROMPT_FOTOS, mensaje, imageBuffer, mediaType, 200) as ResultadoValidacionFoto;
    await logAgentCall({
      agentType: 'FOTO_VALIDACION',
      action: contexto ?? categoria,
      input: { categoria, sizeBytes: imageBuffer.length },
      output: resultado,
      durationMs: Date.now() - start,
      status: 'SUCCESS',
      userId,
    });
    return resultado;
  } catch (err) {
    logger.error('[FotoValidacion] Error validando foto — dejando pasar (fail-open)', {
      categoria, contexto, userId,
      error: err instanceof Error ? err.message : String(err),
    });
    await logAgentCall({
      agentType: 'FOTO_VALIDACION',
      action: contexto ?? categoria,
      input: { categoria, sizeBytes: imageBuffer.length },
      output: { error: err instanceof Error ? err.message : String(err) },
      durationMs: Date.now() - start,
      status: 'ERROR',
      userId,
    });
    // Fail-open: si Claude/la red falla, no bloqueamos al usuario por un
    // problema nuestro — mejor una foto sin revisar que un usuario varado
    // sin poder subir nada por una caída del servicio de IA.
    return { valida: true, razon: 'No se pudo validar automáticamente; se aceptó por defecto.' };
  }
}
