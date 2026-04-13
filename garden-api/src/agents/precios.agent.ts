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

// — Análisis matemático completo devuelto por garden-pricing —
export interface PricingAnalysis {
    // Demanda
    demanda_forecast_7d: number;
    demanda_forecast_30d: number;
    tendencia: 'rising' | 'stable' | 'falling';
    fuerza_tendencia: number;
    // Optimización de precio
    precio_optimo_matematico: number;
    elasticidad_precio: number;
    ingreso_proyectado_actual: number;
    ingreso_proyectado_optimo: number;
    mejora_ingreso_pct: number;
    rango_precio_seguro: { min: number; max: number };
    // Estacionalidad
    factor_estacional_actual: number;
    dias_peak_proximos_7: string[];
    dias_slow_proximos_7: string[];
    patron_semanal: Record<string, number>;
    // Historial
    reservas_7d: number;
    reservas_30d: number;
    reservas_90d: number;
    variacion_vs_mes_anterior_pct: number;
    dias_sin_reserva: number;
    ingreso_promedio_por_reserva: number;
    // Mercado
    percentil_precio_zona: number;
    precio_vs_promedio_zona_pct: number;
    // Metadata
    modelo_usado: string;
    confianza: string;
    puntos_de_datos: number;
}

// — Calcular sugerencia de precio para un cuidador específico —
// precios.agent.ts SOLO RAZONA — garden-pricing hace todos los cálculos.
export async function calcularSugerenciaCuidador(data: {
    caregiverId: string;
    zona: string;
    serviceType: 'PASEO' | 'HOSPEDAJE';
    precioActual: number;
    precioPromedioZona: number;
    precioMinZona: number;
    precioMaxZona: number;
    analysis: PricingAnalysis;
}): Promise<{
    precioSugerido: number;
    porcentajeCambio: number;
    motivo: string;
    explicacion: string;
    debeActualizar: boolean;
}> {
    const a = data.analysis;
    const tendenciaEs = a.tendencia === 'rising' ? 'al alza 📈'
        : a.tendencia === 'falling' ? 'a la baja 📉' : 'estable ➡️';

    const peakStr = a.dias_peak_proximos_7.length > 0
        ? a.dias_peak_proximos_7.join(', ')
        : 'ninguno';
    const slowStr = a.dias_slow_proximos_7.length > 0
        ? a.dias_slow_proximos_7.join(', ')
        : 'ninguno';

    const mensaje = `
Eres el agente de decisión de precios de GARDEN. El motor matemático ya hizo todos los cálculos.
Tu única tarea es RAZONAR con esos números y decidir si el cuidador debe ajustar su precio.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
CONTEXTO DEL CUIDADOR
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Zona: ${data.zona}, Santa Cruz de la Sierra
Servicio: ${data.serviceType === 'PASEO' ? 'Paseo de mascotas' : 'Hospedaje'}
Precio actual: Bs ${data.precioActual}
Precio promedio de la zona: Bs ${data.precioPromedioZona}
Rango en la zona: Bs ${data.precioMinZona} – Bs ${data.precioMaxZona}
Posición en la zona: percentil ${a.percentil_precio_zona.toFixed(0)} (${a.precio_vs_promedio_zona_pct > 0 ? '+' : ''}${a.precio_vs_promedio_zona_pct.toFixed(1)}% vs promedio)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ANÁLISIS MATEMÁTICO (motor Python)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Modelo usado: ${a.modelo_usado} | Confianza: ${a.confianza} | Datos: ${a.puntos_de_datos} días

DEMANDA
  Pronóstico próximos 7 días:  ${a.demanda_forecast_7d.toFixed(1)} reservas/día
  Pronóstico próximos 30 días: ${a.demanda_forecast_30d.toFixed(1)} reservas/día
  Tendencia: ${tendenciaEs} (fuerza: ${(a.fuerza_tendencia * 100).toFixed(0)}%)
  Factor estacional HOY: ${a.factor_estacional_actual.toFixed(2)}x (${a.factor_estacional_actual >= 1.1 ? '⚡ alta demanda' : a.factor_estacional_actual <= 0.85 ? '🔵 baja demanda' : '📊 normal'})
  Días PEAK próximos 7 días: ${peakStr}
  Días SLOW próximos 7 días: ${slowStr}

HISTORIAL
  Reservas últimos 7 días:  ${a.reservas_7d}
  Reservas últimos 30 días: ${a.reservas_30d}
  Reservas últimos 90 días: ${a.reservas_90d}
  Variación vs mes anterior: ${a.variacion_vs_mes_anterior_pct > 0 ? '+' : ''}${a.variacion_vs_mes_anterior_pct.toFixed(1)}%
  Días sin reserva: ${a.dias_sin_reserva}
  Ingreso promedio por reserva: Bs ${a.ingreso_promedio_por_reserva.toFixed(0)}

OPTIMIZACIÓN MATEMÁTICA
  Precio óptimo calculado: Bs ${a.precio_optimo_matematico}
  Elasticidad precio-demanda: ${a.elasticidad_precio.toFixed(2)} (${a.elasticidad_precio < -1 ? 'elástica — bajar precio puede aumentar ingresos' : 'inelástica — subir precio aumenta ingresos'})
  Ingreso proyectado (precio actual):  Bs ${a.ingreso_proyectado_actual.toFixed(0)}/semana
  Ingreso proyectado (precio óptimo):  Bs ${a.ingreso_proyectado_optimo.toFixed(0)}/semana
  Mejora potencial de ingresos: ${a.mejora_ingreso_pct > 0 ? '+' : ''}${a.mejora_ingreso_pct.toFixed(1)}%
  Rango seguro de precio: Bs ${a.rango_precio_seguro.min} – Bs ${a.rango_precio_seguro.max}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
REGLAS ESTRICTAS (no negociables)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
1. precioSugerido DEBE estar dentro de: Bs ${a.rango_precio_seguro.min} – Bs ${a.rango_precio_seguro.max}
2. Si la mejora de ingresos proyectada < 5% → debeActualizar: false
3. Si dias_sin_reserva > 14 → baja precio para atraer (prioridad alta)
4. Si tendencia al alza + factor estacional > 1.1 → sube precio
5. Si precio actual ya está en el precio óptimo (±5%) → debeActualizar: false
6. La explicacion debe ser en boliviano natural, amigable, sin jerga técnica

Responde con este JSON exacto:
{
  "precioSugerido": numero entero en Bs,
  "porcentajeCambio": numero entero (positivo = sube, negativo = baja),
  "motivo": "máximo 4 palabras",
  "explicacion": "2 oraciones amigables al cuidador explicando el beneficio concreto",
  "debeActualizar": true | false
}
    `;

    return await callClaude(SYSTEM_PROMPT_PRECIOS, mensaje, 600);
}
