/**
 * Agente de Verificación de Antecedentes Penales — revisa el documento
 * FELCC/REJAP que un cuidador sube voluntariamente en la sección
 * "Documentos" de su perfil (filtro opcional, no bloquea el marketplace).
 *
 * Evalúa DOS cosas distintas:
 * 1. Si el documento parece legítimo (no editado con Photoshop, no
 *    generado por IA, consistente con el formato real de un FELCC/REJAP
 *    boliviano).
 * 2. Si el documento muestra antecedentes penales explícitos de maltrato
 *    animal o violencia.
 *
 * A diferencia de foto-validacion.agent.ts (que falla abierto porque una
 * foto de perfil rechazada por error no tiene consecuencias serias), este
 * agente NUNCA decide una suspensión por sí solo — solo marca el documento
 * para que un admin humano lo revise (ver caregiver-profile.service.ts).
 * Tampoco falla "abierto" hacia limpio ante un error técnico: un fallo de
 * Claude/red deja el documento en EN_REVISION (cola de admin), nunca lo
 * limpia solo, porque limpiar en silencio podría ocultar un antecedente real.
 */
import { callClaudeVision } from '../services/claude.service.js';
import { logAgentCall } from '../shared/agent-logger.js';
import logger from '../shared/logger.js';

const SYSTEM_PROMPT_ANTECEDENTES = `
Eres el Agente de Verificación de Antecedentes de GARDEN, una plataforma de
cuidado de mascotas en Santa Cruz de la Sierra, Bolivia. Un cuidador subió un
documento que dice ser su Certificado FELCC (Fuerza Especial de Lucha Contra
el Crimen) o REJAP (Registro Judicial de Antecedentes Penales) de Bolivia.

Tu única función es evaluar dos cosas:

1. "documentoLicito": si el documento parece un FELCC/REJAP boliviano real y
   sin editar — busca inconsistencias de fuente, alineación, artefactos de
   edición, sellos/membretes que no calcen, o cualquier señal de que fue
   generado o alterado digitalmente (Photoshop, IA generativa, etc.). Sé
   razonable: una foto de mala calidad, con reflejo de luz, o ligeramente
   torcida SIGUE siendo lícita si el contenido es consistente y real.

2. "antecedentesDetectados": si el documento indica explícitamente que la
   persona SÍ tiene antecedentes penales relacionados con maltrato animal o
   violencia (agresión, lesiones, violencia intrafamiliar, homicidio, etc.).
   Si el documento dice que no tiene antecedentes, o los antecedentes que
   muestra no son de violencia/maltrato animal, esto debe ser "false".

Ante la duda razonable, no marques como ilícito ni con antecedentes — deja
que un humano decida (por eso NO tomas la decisión final, solo marcas).

Responde ÚNICAMENTE en formato JSON válido, sin texto adicional:
{
  "documentoLicito": true o false,
  "antecedentesDetectados": true o false,
  "razon": "máximo 2 oraciones en español explicando tu evaluación, para que un admin la lea"
}
`;

export interface ResultadoAntecedentes {
  documentoLicito: boolean;
  antecedentesDetectados: boolean;
  razon: string;
}

export async function verificarAntecedentes(params: {
  documentBuffer: Buffer;
  mediaType: 'image/jpeg' | 'image/png' | 'image/webp' | 'image/gif' | 'application/pdf';
  userId?: string;
}): Promise<ResultadoAntecedentes | null> {
  const { documentBuffer, mediaType, userId } = params;
  const start = Date.now();

  try {
    const resultado = await callClaudeVision(
      SYSTEM_PROMPT_ANTECEDENTES,
      '¿Este documento es un FELCC/REJAP lícito y muestra antecedentes de maltrato animal o violencia? Responde con el JSON pedido.',
      documentBuffer,
      mediaType,
      400
    ) as ResultadoAntecedentes;

    if (typeof resultado?.documentoLicito !== 'boolean' || typeof resultado?.antecedentesDetectados !== 'boolean') {
      throw new Error('Respuesta sin campos documentoLicito/antecedentesDetectados válidos');
    }

    await logAgentCall({
      agentType: 'DOCUMENTO_ANTECEDENTES',
      action: 'verificar_antecedentes',
      input: { mediaType, sizeBytes: documentBuffer.length },
      output: resultado,
      durationMs: Date.now() - start,
      status: 'SUCCESS',
      userId,
    });
    return resultado;
  } catch (err) {
    logger.error('[DocumentoAntecedentes] Fallo técnico — queda en revisión manual (no falla abierto)', {
      userId,
      error: err instanceof Error ? err.message : String(err),
    });
    await logAgentCall({
      agentType: 'DOCUMENTO_ANTECEDENTES',
      action: 'verificar_antecedentes',
      input: { mediaType, sizeBytes: documentBuffer.length },
      output: { error: err instanceof Error ? err.message : String(err) },
      durationMs: Date.now() - start,
      status: 'ERROR',
      userId,
    });
    // A diferencia de foto-validacion (fail-open porque el riesgo es bajo),
    // acá un fallo técnico NO limpia el documento — devuelve null para que
    // el caller lo deje en EN_REVISION, a la espera de un admin.
    return null;
  }
}
