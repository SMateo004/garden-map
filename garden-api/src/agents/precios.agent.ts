import { callClaude } from '../services/claude.service.js';

const SYSTEM_PROMPT_PRECIOS = `
Eres el Agente de Precios de GARDEN, una plataforma de cuidado de 
mascotas en Santa Cruz de la Sierra, Bolivia. Los precios son en 
bolivianos (Bs).

Tu función es ayudar a los cuidadores a ser competitivos y rentables, 
y explicar los precios a los dueños de forma transparente y amigable.

Nunca sugieras ajustes por encima del +20% ni por debajo del -15%.
Usa lenguaje boliviano natural y cercano, nunca jerga técnica.
Responde ÚNICAMENTE en formato JSON válido, sin texto adicional.
`;

// — Sugerir precio durante el onboarding del cuidador —
export async function sugerirPrecioOnboarding(data: {
    zona: string;
    servicio: string;
    experienciaMeses: number;
    trustScore: number;
    precioPromedioZona: number;
    precioMinZona: number;
    precioMaxZona: number;
}): Promise<{
    precioSugerido: number;
    rangoRecomendado: { min: number; max: number };
    justificacion: string;
    posicionEnMercado: 'competitivo' | 'premium' | 'economico';
}> {
    const mensaje = `
Sugiere un precio inicial para este cuidador:

Zona: ${data.zona}, Santa Cruz de la Sierra
Servicio: ${data.servicio}
Experiencia: ${data.experienciaMeses} meses
Trust Score: ${data.trustScore}/100
Precio promedio en su zona: Bs ${data.precioPromedioZona}
Rango en su zona: Bs ${data.precioMinZona} - Bs ${data.precioMaxZona}

Responde con este JSON exacto:
{
  "precioSugerido": numero en Bs,
  "rangoRecomendado": { "min": numero, "max": numero },
  "justificacion": "máximo 2 oraciones simples y amigables",
  "posicionEnMercado": "competitivo" | "premium" | "economico"
}
  `;

    return await callClaude(SYSTEM_PROMPT_PRECIOS, mensaje, 512);
}

// — Calcular ajuste dinámico por zona (corre cada noche como job) —
export async function calcularAjusteDinamico(data: {
    zona: string;
    servicio: string;
    ocupacionUltimos30Dias: number;
    reservasUltimos7Dias: number;
    reservasMismoPeriodoMesAnterior: number;
    eventosProximos: string[];
    fechaConsulta: string;
}): Promise<{
    multiplicador: number;
    porcentajeAjuste: number;
    aplicarDesde: string;
    aplicarHasta: string;
    motivo: string;
    explicacionParaDueno: string;
    cuandoVuelveNormal: string;
    confianzaPronostico: 'alta' | 'media' | 'baja';
}> {
    const mensaje = `
Calcula el ajuste de precio para esta zona:

Zona: ${data.zona}, Santa Cruz de la Sierra
Servicio: ${data.servicio}
Ocupación promedio últimos 30 días: ${(data.ocupacionUltimos30Dias * 100).toFixed(0)}%
Reservas últimos 7 días: ${data.reservasUltimos7Dias}
Reservas mismo período mes anterior: ${data.reservasMismoPeriodoMesAnterior}
Eventos próximos: ${data.eventosProximos.join(', ') || 'ninguno'}
Fecha de consulta: ${data.fechaConsulta}

Responde con este JSON exacto:
{
  "multiplicador": numero (ej: 1.15 para +15%, 1.0 para sin cambio),
  "porcentajeAjuste": numero entero (ej: 15 para +15%, 0 para sin cambio),
  "aplicarDesde": "YYYY-MM-DD",
  "aplicarHasta": "YYYY-MM-DD",
  "motivo": "razón breve en 3 palabras máximo",
  "explicacionParaDueno": "2 oraciones amigables explicando el ajuste",
  "cuandoVuelveNormal": "texto como 'A partir del 24 de marzo'",
  "confianzaPronostico": "alta" | "media" | "baja"
}
  `;

    return await callClaude(SYSTEM_PROMPT_PRECIOS, mensaje, 512);
}

// — Explicación puntual del badge de temporada alta —
export async function explicarBadgeTemporadaAlta(data: {
    zona: string;
    porcentajeAjuste: number;
    motivo: string;
    fechaVueltaNormal: string;
}): Promise<{
    titulo: string;
    explicacion: string;
    cuandoVuelveNormal: string;
}> {
    const mensaje = `
El dueño presionó el badge de temporada alta. Explícale de forma 
amigable por qué el precio está ajustado:

Zona: ${data.zona}
Ajuste: +${data.porcentajeAjuste}%
Motivo: ${data.motivo}
Fecha vuelta a precio normal: ${data.fechaVueltaNormal}

Responde con este JSON exacto:
{
  "titulo": "máximo 4 palabras",
  "explicacion": "2 oraciones simples y amigables, nada técnico",
  "cuandoVuelveNormal": "una frase corta con la fecha"
}
  `;

    return await callClaude(SYSTEM_PROMPT_PRECIOS, mensaje, 256);
}
