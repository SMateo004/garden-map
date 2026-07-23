/**
 * Agente de Coherencia de Texto — revisa que lo que un cuidador escribe en
 * los campos de texto libre de su perfil profesional (bio, experiencia,
 * políticas de cuidado, etc.) tenga sentido, ya que ese texto se muestra
 * tal cual en el perfil comercial que ve el cliente. No es un chequeo de
 * ortografía ni de estilo — solo detecta relleno sin sentido (mecaneo de
 * teclado), texto irrelevante al campo, o spam.
 *
 * Igual que precios.agent.ts: sin logAgentCall explícito — se llama con
 * debounce mientras el cuidador escribe, y loguear cada intento en
 * AgentLog inundaría el Monitor de Agentes del panel admin sin aportar
 * nada (a diferencia de foto-validacion.agent.ts, que es una llamada
 * puntual por foto subida).
 */
import { callClaude } from '../services/claude.service.js';
import logger from '../shared/logger.js';

const SYSTEM_PROMPT_COHERENCIA = `
Eres un revisor rápido de perfiles para GARDEN, un marketplace de cuidado
de mascotas en Santa Cruz de la Sierra, Bolivia. Un cuidador escribió texto
para un campo de su perfil profesional, que se muestra tal cual a los
clientes que buscan contratarlo.

Tu única función es juzgar si el texto es coherente y tiene sentido como
contenido real para ese campo — NO evalúes ortografía menor, estilo, ni
qué tan convincente es. Marca como NO coherente únicamente cuando sea:
- Relleno sin sentido / mecaneo de teclado (ej: "frctbybuvtbrh", "asdasdasd")
- Texto en un idioma que no es español ni claramente relacionado al cuidado de mascotas
- Spam, publicidad de otra cosa, o contenido ofensivo
- Completamente irrelevante al campo (ej: una receta de cocina en el campo de biografía)

Si tiene sentido aunque sea corto, informal, o con errores de tipeo — es coherente.
Sé permisivo por defecto: ante la duda, es coherente.

Responde ÚNICAMENTE en formato JSON válido, sin texto adicional.
`;

export interface ResultadoCoherenciaTexto {
  coherente: boolean;
  razon?: string;
}

/**
 * Nunca lanza por un texto incoherente (eso es un resultado válido,
 * `coherente: false`) — solo puede fallar por un problema técnico con
 * Claude, y en ese caso falla abierto (coherente: true) para no bloquear
 * el guardado del perfil por una falla de un servicio externo opcional.
 */
export async function verificarCoherenciaTexto(campo: string, texto: string): Promise<ResultadoCoherenciaTexto> {
  const trimmed = texto.trim();
  if (trimmed.length < 10) return { coherente: true };

  const mensaje = `
Campo: "${campo}"
Texto a revisar:
"""
${trimmed}
"""

Responde con este JSON exacto:
{
  "coherente": true o false,
  "razon": "razón breve en español, máx 15 palabras, solo si coherente es false"
}
  `;

  try {
    const resultado = await callClaude(SYSTEM_PROMPT_COHERENCIA, mensaje, 150) as ResultadoCoherenciaTexto;
    if (typeof resultado?.coherente !== 'boolean') throw new Error('respuesta sin campo coherente válido');
    return resultado;
  } catch (err) {
    logger.warn('[texto-coherencia.agent] fallo técnico, se falla abierto', { campo, error: (err as Error).message });
    return { coherente: true };
  }
}
