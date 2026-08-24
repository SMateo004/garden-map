/**
 * Agente de Verificación de NIT — revisa el documento de NIT (Número de
 * Identificación Tributaria, Bolivia) que el dueño de una cuenta EMPRESA
 * sube al registrarse o desde su perfil.
 *
 * A diferencia de documento-antecedentes.agent.ts, este agente solo evalúa
 * UNA cosa (si el documento se ve auténtico) — no hay una segunda señal
 * "punitiva" que decidir. Y a diferencia de antecedentes, NO existe una vía
 * de auto-aprobación: el resultado de este agente es solo contexto para que
 * un admin humano decida siempre a mano (ver caregiver-profile.service.ts
 * submitNitDocument — el status queda en EN_REVISION sin importar el
 * veredicto). No depende de ninguna API oficial del gobierno boliviano.
 *
 * Nunca falla "abierto": un error técnico de Claude/red devuelve null, y el
 * caller lo deja igual en EN_REVISION a la espera de un admin.
 */
import { callClaudeVision } from '../services/claude.service.js';
import { logAgentCall } from '../shared/agent-logger.js';
import logger from '../shared/logger.js';

const SYSTEM_PROMPT_NIT = `
Eres el Agente de Verificación de NIT de GARDEN, una plataforma de cuidado de
mascotas en Santa Cruz de la Sierra, Bolivia. El dueño de una empresa (hotel,
guardería, etc.) subió un documento que dice ser su NIT (Número de
Identificación Tributaria) — normalmente un certificado o impresión del
Servicio de Impuestos Nacionales (SIN) de Bolivia.

Tu única función es evaluar "documentoLicito": si el documento parece un NIT
boliviano real y sin editar — busca inconsistencias de fuente, alineación,
artefactos de edición, formato/membrete que no calce con el SIN, o cualquier
señal de que fue generado o alterado digitalmente (Photoshop, IA generativa,
etc.). Sé razonable: una foto de mala calidad, con reflejo de luz, o
ligeramente torcida SIGUE siendo lícita si el contenido es consistente y real.

Ante la duda razonable, no marques como ilícito — deja que un humano decida
(por eso NO tomas la decisión final, solo das contexto).

Responde ÚNICAMENTE en formato JSON válido, sin texto adicional:
{
  "documentoLicito": true o false,
  "razon": "máximo 2 oraciones en español explicando tu evaluación, para que un admin la lea"
}
`;

export interface ResultadoNit {
  documentoLicito: boolean;
  razon: string;
}

export async function verificarNit(params: {
  documentBuffer: Buffer;
  mediaType: 'image/jpeg' | 'image/png' | 'image/webp' | 'image/gif' | 'application/pdf';
  userId?: string;
}): Promise<ResultadoNit | null> {
  const { documentBuffer, mediaType, userId } = params;
  const start = Date.now();

  try {
    const resultado = await callClaudeVision(
      SYSTEM_PROMPT_NIT,
      '¿Este documento es un NIT boliviano lícito? Responde con el JSON pedido.',
      documentBuffer,
      mediaType,
      300
    ) as ResultadoNit;

    if (typeof resultado?.documentoLicito !== 'boolean') {
      throw new Error('Respuesta sin campo documentoLicito válido');
    }

    await logAgentCall({
      agentType: 'NIT_VERIFICATION',
      action: 'verificar_nit',
      input: { mediaType, sizeBytes: documentBuffer.length },
      output: resultado,
      durationMs: Date.now() - start,
      status: 'SUCCESS',
      userId,
    });
    return resultado;
  } catch (err) {
    logger.error('[NitVerification] Fallo técnico — queda en revisión manual (no falla abierto)', {
      userId,
      error: err instanceof Error ? err.message : String(err),
    });
    await logAgentCall({
      agentType: 'NIT_VERIFICATION',
      action: 'verificar_nit',
      input: { mediaType, sizeBytes: documentBuffer.length },
      output: { error: err instanceof Error ? err.message : String(err) },
      durationMs: Date.now() - start,
      status: 'ERROR',
      userId,
    });
    return null;
  }
}
