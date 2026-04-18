import { callClaude } from '../services/claude.service.js';

const SYSTEM_PROMPT_REPUTACION = `
Eres el Agente de Reputación de GARDEN, una plataforma de cuidado de
mascotas en Santa Cruz de la Sierra, Bolivia. Tu función es proteger
la integridad del sistema de calificaciones y ayudar a resolver
disputas de forma justa.

Cuando analices una reputación: evalúa si la nueva calificación es
consistente con el historial del cuidador y si hay señales de
manipulación o fraude.

Cuando resuelvas una disputa: analiza todos los datos y genera un
análisis objetivo. Sé directo. El administrador debe poder tomar una
decisión en menos de 2 minutos.

CONTEXTO DE EXTENSIONES DE PASEO:
- Los paseos de 30 o 60 minutos pueden ampliarse durante el servicio en curso
  en tramos de 15, 30 o 60 minutos adicionales, confirmados por el cliente.
- Cada extensión queda registrada en serviceEvents como tipo EXTENSION_CONFIRMED.
- La duración total de la reserva y el monto pagado se actualizan automáticamente.
- Al analizar disputas de PASEO, verifica si hubo extensiones: un cuidador que
  continúa más allá del tiempo original podría tener una extensión aprobada.

Responde siempre en español. Responde ÚNICAMENTE en formato JSON
válido, sin texto adicional, sin bloques de código markdown.
`;

// — Analizar si una calificación es válida o sospechosa —
export async function analizarCalificacion(data: {
    calificacionNueva: number;
    cuidadorId: string;
    historialCalificaciones: number[];
    calificacionPromedio: number;
    totalResenas: number;
    tiempoEnPlataforma: string;
    duenoHistorial: number[];
}): Promise<{
    veredicto: 'calificacion_valida' | 'calificacion_sospechosa';
    motivo: string;
    nivelConfianza: 'alto' | 'medio' | 'bajo';
}> {
    const mensaje = `
Analiza esta nueva calificación:

Nueva calificación: ${data.calificacionNueva} estrellas
Historial del cuidador (últimas calificaciones): ${data.historialCalificaciones.join(', ')}
Promedio actual: ${data.calificacionPromedio}
Total de reseñas: ${data.totalResenas}
Tiempo en plataforma: ${data.tiempoEnPlataforma}
Historial de calificaciones que ha dado este dueño: ${data.duenoHistorial.join(', ')}

Responde con este JSON exacto:
{
  "veredicto": "calificacion_valida" | "calificacion_sospechosa",
  "motivo": "explicación breve en máximo 2 oraciones",
  "nivelConfianza": "alto" | "medio" | "bajo"
}
  `;

    return await callClaude(SYSTEM_PROMPT_REPUTACION, mensaje, 512);
}

// — Analizar una disputa y recomendar resolución —
export async function analizarDisputa(data: {
    reserva: object;
    cuidador: object;
    dueno: object;
    mascota: object;
    motivoDisputa: string;
    mensajesRelevantes?: string[];
}): Promise<{
    veredicto: 'liberar_al_cuidador' | 'devolver_al_dueno' | 'revision_manual';
    resumen: string;
    credibilidadCuidador: number;
    credibilidadDueno: number;
    recomendacion: string;
    fundamento: string;
    nivelConfianza: 'alto' | 'medio' | 'bajo';
}> {
    const mensaje = `
Analiza esta disputa y recomienda una resolución:

DATOS DE LA RESERVA:
${JSON.stringify(data.reserva, null, 2)}

DATOS DEL CUIDADOR:
${JSON.stringify(data.cuidador, null, 2)}

DATOS DEL DUEÑO:
${JSON.stringify(data.dueno, null, 2)}

MASCOTA:
${JSON.stringify(data.mascota, null, 2)}

MOTIVO DE LA DISPUTA:
${data.motivoDisputa}

${data.mensajesRelevantes && data.mensajesRelevantes.length > 0 ? `MENSAJES RELEVANTES:\n${data.mensajesRelevantes.join('\n')}` : ''}

Responde con este JSON exacto:
{
  "veredicto": "liberar_al_cuidador" | "devolver_al_dueno" | "revision_manual",
  "resumen": "resumen objetivo en máximo 3 oraciones",
  "credibilidadCuidador": numero del 0 al 100,
  "credibilidadDueno": numero del 0 al 100,
  "recomendacion": "qué hacer con el escrow en una oración",
  "fundamento": "por qué en máximo 2 oraciones",
  "nivelConfianza": "alto" | "medio" | "bajo"
}
  `;

    return await callClaude(SYSTEM_PROMPT_REPUTACION, mensaje, 1024);
}
