import cron from 'node-cron';
import { calcularAjusteDinamico, calcularSugerenciaCuidador, PricingAnalysis } from '../agents/precios.agent.js';
import prisma from '../config/database.js';
import logger from '../shared/logger.js';

const ZONAS_SANTA_CRUZ = [
    'Equipetrol', 'Las Palmas', 'Plan 3000', 'Norte',
    'Sur', 'Centro', 'Urbarí', 'Villa 1ro de Mayo', 'Urubo'
];

const SERVICIOS = ['hospedaje', 'paseo'];

const PRICING_SERVICE_URL = process.env.PRICING_SERVICE_URL || 'http://localhost:8000';

export function iniciarJobAjustePrecios() {
    // Corre todos los días a las 2am
    cron.schedule('0 2 * * *', async () => {
        logger.info('[PRICING JOB] Iniciando ajuste dinámico de precios...');
        await runPricingJob();
    });
}

export async function runPricingJob() {
    // Verificar si los precios dinámicos están habilitados
    const { getBoolSetting } = await import('../utils/settings-cache.js');
    if (!await getBoolSetting('preciosDinamicosEnabled', true)) {
        logger.info('[PRICING JOB] Precios dinámicos deshabilitados por admin. Saltando...');
        return;
    }

    // 1. Ajustes por zona (AjustePrecio — afecta al marketplace general)
    for (const zona of ZONAS_SANTA_CRUZ) {
        for (const servicio of SERVICIOS) {
            try {
                const datos = await obtenerDatosZona(zona, servicio);
                const ajuste = await calcularAjusteDinamico(datos);

                await prisma.ajustePrecio.upsert({
                    where: { zona_servicio: { zona, servicio } },
                    update: {
                        multiplicador: ajuste.multiplicador,
                        porcentajeAjuste: ajuste.porcentajeAjuste,
                        aplicarDesde: new Date(ajuste.aplicarDesde),
                        aplicarHasta: new Date(ajuste.aplicarHasta),
                        motivo: ajuste.motivo,
                        explicacionParaDueno: ajuste.explicacionParaDueno,
                        cuandoVuelveNormal: ajuste.cuandoVuelveNormal,
                    },
                    create: {
                        zona, servicio,
                        multiplicador: ajuste.multiplicador,
                        porcentajeAjuste: ajuste.porcentajeAjuste,
                        aplicarDesde: new Date(ajuste.aplicarDesde),
                        aplicarHasta: new Date(ajuste.aplicarHasta),
                        motivo: ajuste.motivo,
                        explicacionParaDueno: ajuste.explicacionParaDueno,
                        cuandoVuelveNormal: ajuste.cuandoVuelveNormal,
                    },
                });
            } catch (err) {
                logger.error(`[PRICING JOB] Error zona ${zona}/${servicio}:`, err);
            }
        }
    }

    // 2. Sugerencias por cuidador (SugerenciaPrecio — para el botón de confirmación)
    await generarSugerenciasPorCuidador();

    logger.info('[PRICING JOB] Completado.');
}

async function generarSugerenciasPorCuidador() {
    const caregivers = await prisma.caregiverProfile.findMany({
        where: { status: 'APPROVED' },
        select: {
            id: true,
            zone: true,
            pricePerDay: true,
            pricePerWalk30: true,
            pricePerWalk60: true,
        },
    });

    logger.info(`[PRICING JOB] Generando sugerencias para ${caregivers.length} cuidadores...`);

    for (const cg of caregivers) {
        const zona = cg.zone || 'Centro';

        // Generar sugerencia para PASEO
        if (cg.pricePerWalk30 != null) {
            await generarSugerenciaCuidador(cg.id, zona, 'PASEO', cg.pricePerWalk30);
        }

        // Generar sugerencia para HOSPEDAJE
        if (cg.pricePerDay != null) {
            await generarSugerenciaCuidador(cg.id, zona, 'HOSPEDAJE', cg.pricePerDay);
        }
    }
}

async function generarSugerenciaCuidador(
    caregiverId: string,
    zona: string,
    serviceType: 'PASEO' | 'HOSPEDAJE',
    precioActual: number
) {
    try {
        // No generar si ya hay una sugerencia PENDING reciente (< 48h)
        const existing = await prisma.sugerenciaPrecio.findFirst({
            where: {
                caregiverId,
                serviceType,
                status: 'PENDING',
                expiresAt: { gt: new Date() },
            },
        });
        if (existing) return;

        const serviceFilter = serviceType === 'PASEO' ? 'PASEO' : 'HOSPEDAJE';

        // Obtener historial de reservas de este cuidador
        const bookings = await prisma.booking.findMany({
            where: {
                caregiver: { id: caregiverId },
                serviceType: serviceFilter,
                status: { in: ['COMPLETED', 'IN_PROGRESS', 'CONFIRMED'] },
                createdAt: { gte: new Date(Date.now() - 90 * 24 * 60 * 60 * 1000) },
            },
            select: { createdAt: true, totalAmount: true },
            orderBy: { createdAt: 'asc' },
        });

        // Agrupar por día para el microservicio
        const dailyMap: Record<string, { count: number; revenue: number }> = {};
        for (const b of bookings) {
            const day = b.createdAt.toISOString().split('T')[0]!;
            if (!dailyMap[day]) dailyMap[day] = { count: 0, revenue: 0 };
            dailyMap[day].count++;
            dailyMap[day].revenue += Number(b.totalAmount);
        }
        const history = Object.entries(dailyMap).map(([date, v]) => ({
            date, count: v.count, revenue: v.revenue,
        }));

        // Estadísticas de zona para comparación (necesarias para el /analyze)
        const zonePrices = await obtenerPreciosZona(zona, serviceType);

        // Llamar al microservicio Python → análisis matemático completo
        const fallbackAnalysis: PricingAnalysis = {
            demanda_forecast_7d: 2.0,
            demanda_forecast_30d: 2.0,
            tendencia: 'stable',
            fuerza_tendencia: 0.0,
            precio_optimo_matematico: precioActual,
            elasticidad_precio: serviceType === 'PASEO' ? -1.2 : -0.8,
            ingreso_proyectado_actual: precioActual * 2,
            ingreso_proyectado_optimo: precioActual * 2,
            mejora_ingreso_pct: 0.0,
            rango_precio_seguro: {
                min: Math.max(zonePrices.min, Math.round(precioActual * 0.85)),
                max: Math.min(zonePrices.max, Math.round(precioActual * 1.20)),
            },
            factor_estacional_actual: 1.0,
            dias_peak_proximos_7: [],
            dias_slow_proximos_7: [],
            patron_semanal: { lunes: 0.70, martes: 0.70, miercoles: 0.75, jueves: 0.80, viernes: 1.10, sabado: 1.30, domingo: 1.20 },
            reservas_7d: 0,
            reservas_30d: 0,
            reservas_90d: 0,
            variacion_vs_mes_anterior_pct: 0,
            dias_sin_reserva: 30,
            ingreso_promedio_por_reserva: precioActual,
            percentil_precio_zona: 50,
            precio_vs_promedio_zona_pct: 0,
            modelo_usado: 'reglas',
            confianza: 'baja',
            puntos_de_datos: 0,
        };

        let analysis: PricingAnalysis = fallbackAnalysis;
        try {
            const resp = await fetch(`${PRICING_SERVICE_URL}/analyze`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    service_type: serviceType,
                    history: history.map(h => ({ ...h, price: precioActual })),
                    precio_actual: precioActual,
                    precio_promedio_zona: zonePrices.avg,
                    precio_min_zona: zonePrices.min,
                    precio_max_zona: zonePrices.max,
                    forecast_days: 7,
                }),
                signal: AbortSignal.timeout(30000),
            });
            if (resp.ok) {
                analysis = await resp.json() as PricingAnalysis;
                logger.info(`[PRICING JOB] Python analysis OK for ${caregiverId} (${analysis.modelo_usado}, confianza: ${analysis.confianza})`);
            } else {
                logger.warn(`[PRICING JOB] Python service returned ${resp.status} for ${caregiverId}, using fallback`);
            }
        } catch (err) {
            logger.warn(`[PRICING JOB] Python service unavailable for ${caregiverId}, using fallback`);
        }

        // Llamar a Claude para la decisión final (solo razonamiento, no cálculos)
        const sugerencia = await calcularSugerenciaCuidador({
            caregiverId,
            zona,
            serviceType,
            precioActual,
            precioPromedioZona: zonePrices.avg,
            precioMinZona: zonePrices.min,
            precioMaxZona: zonePrices.max,
            analysis,
        });

        if (!sugerencia.debeActualizar) return;

        const expiresAt = new Date(Date.now() + 48 * 60 * 60 * 1000);

        await prisma.sugerenciaPrecio.create({
            data: {
                caregiverId,
                serviceType,
                precioActual,
                precioSugerido: sugerencia.precioSugerido,
                porcentajeCambio: sugerencia.porcentajeCambio,
                motivo: sugerencia.motivo,
                explicacion: sugerencia.explicacion,
                confianza: analysis.confianza,
                modeloUsado: analysis.modelo_usado,
                tendencia: analysis.tendencia,
                status: 'PENDING',
                expiresAt,
            },
        });

        logger.info(`[PRICING JOB] Sugerencia creada para cuidador ${caregiverId} (${serviceType}): Bs ${precioActual} → Bs ${sugerencia.precioSugerido}`);
    } catch (err) {
        logger.error(`[PRICING JOB] Error generando sugerencia para ${caregiverId}/${serviceType}:`, err);
    }
}

async function obtenerPreciosZona(zona: string, serviceType: 'PASEO' | 'HOSPEDAJE') {
    const field = serviceType === 'PASEO' ? 'pricePerWalk30' : 'pricePerDay';
    const caregivers = await prisma.caregiverProfile.findMany({
        where: { zone: zona as any, status: 'APPROVED', [field]: { not: null } },
        select: { [field]: true },
    });

    const prices = caregivers
        .map((c: any) => c[field] as number)
        .filter((p: number) => p > 0);

    if (prices.length === 0) return { avg: 50, min: 30, max: 100 };
    return {
        avg: Math.round(prices.reduce((a: number, b: number) => a + b, 0) / prices.length),
        min: Math.min(...prices),
        max: Math.max(...prices),
    };
}

async function obtenerDatosZona(zona: string, servicio: string) {
    const hoy = new Date();
    const hace7Dias = new Date(hoy.getTime() - 7 * 24 * 60 * 60 * 1000);
    const hace37Dias = new Date(hoy.getTime() - 37 * 24 * 60 * 60 * 1000);

    const serviceType = servicio === 'paseo' ? 'PASEO' : 'HOSPEDAJE';

    const [reservas7, reservas7ant] = await Promise.all([
        prisma.booking.count({
            where: {
                serviceType,
                status: { in: ['CONFIRMED', 'IN_PROGRESS', 'COMPLETED'] },
                createdAt: { gte: hace7Dias },
            },
        }),
        prisma.booking.count({
            where: {
                serviceType,
                status: { in: ['CONFIRMED', 'IN_PROGRESS', 'COMPLETED'] },
                createdAt: { gte: hace37Dias, lt: hace7Dias },
            },
        }),
    ]);

    const totalCaregivers = await prisma.caregiverProfile.count({
        where: { zone: zona as any, status: 'APPROVED' },
    });

    const ocupacion = totalCaregivers > 0
        ? Math.min(1, reservas7 / Math.max(1, totalCaregivers * 7 * 0.3))
        : 0.5;

    const feriados = obtenerFeriadosProximos();

    return {
        zona,
        servicio,
        ocupacionUltimos30Dias: ocupacion,
        reservasUltimos7Dias: reservas7,
        reservasMismoPeriodoMesAnterior: reservas7ant,
        eventosProximos: feriados,
        fechaConsulta: hoy.toISOString().split('T')[0]!,
    };
}

function obtenerFeriadosProximos(): string[] {
    const hoy = new Date();
    const en15Dias = new Date(hoy.getTime() + 15 * 24 * 60 * 60 * 1000);

    const feriadosBolivia: { fecha: string; nombre: string }[] = [
        { fecha: '01-01', nombre: 'Año Nuevo' },
        { fecha: '22-01', nombre: 'Día del Estado Plurinacional' },
        { fecha: '12-10', nombre: 'Día de la Hispanidad' },
        { fecha: '02-11', nombre: 'Día de los Difuntos' },
        { fecha: '25-12', nombre: 'Navidad' },
        { fecha: '01-05', nombre: 'Día del Trabajo' },
        { fecha: '06-08', nombre: 'Día de la Independencia' },
        { fecha: '27-05', nombre: 'Día de la Madre' },
    ];

    const proximos: string[] = [];
    for (const f of feriadosBolivia) {
        const [day, month] = f.fecha.split('-').map(Number);
        const fechaEsteAnio = new Date(hoy.getFullYear(), month! - 1, day);
        const fechaProxAnio = new Date(hoy.getFullYear() + 1, month! - 1, day);

        if (fechaEsteAnio >= hoy && fechaEsteAnio <= en15Dias) {
            proximos.push(f.nombre);
        } else if (fechaProxAnio >= hoy && fechaProxAnio <= en15Dias) {
            proximos.push(f.nombre);
        }
    }
    return proximos;
}
