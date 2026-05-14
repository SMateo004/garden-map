import cron from 'node-cron';
import {
    calcularAjusteDinamico,
    calcularSugerenciaCuidador,
    sugerirPrecioParaCuidador,
    PricingAnalysis,
} from '../agents/precios.agent.js';
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
        // Convention: pricePerWalk60 es el precio canónico; walk30 = walk60 / 2
        const paseoPrecio = cg.pricePerWalk60 ?? (cg.pricePerWalk30 != null ? cg.pricePerWalk30 * 2 : null);
        if (paseoPrecio != null) {
            await generarSugerenciaCuidador(cg.id, zona, 'PASEO', paseoPrecio);
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
        const existing = await prisma.sugerenciaPrecio.findFirst({
            where: { caregiverId, serviceType, status: 'PENDING', expiresAt: { gt: new Date() } },
        });
        if (existing) return;

        const now = Date.now();
        const hace7  = new Date(now - 7  * 86400000);
        const hace30 = new Date(now - 30 * 86400000);
        const hace60 = new Date(now - 60 * 86400000);
        const hace90 = new Date(now - 90 * 86400000);

        const bookings = await prisma.booking.findMany({
            where: {
                caregiverId,
                serviceType,
                status: { in: ['COMPLETED', 'IN_PROGRESS', 'CONFIRMED'] },
                createdAt: { gte: hace90 },
            },
            select: { createdAt: true, totalAmount: true },
            orderBy: { createdAt: 'desc' },
        });

        const reservas7d  = bookings.filter(b => b.createdAt >= hace7).length;
        const reservas30d = bookings.filter(b => b.createdAt >= hace30).length;
        const reservas90d = bookings.length;
        const reservasMesAnterior = bookings.filter(b => b.createdAt >= hace60 && b.createdAt < hace30).length;
        const variacionVsMesAnteriorPct = reservasMesAnterior === 0
            ? (reservas30d > 0 ? 100 : 0)
            : Math.round(((reservas30d - reservasMesAnterior) / reservasMesAnterior) * 100);
        const diasSinReserva = bookings.length === 0
            ? 90
            : Math.floor((now - bookings[0]!.createdAt.getTime()) / 86400000);

        const zonePrices = await obtenerPreciosZona(zona, serviceType);

        // Construir historial diario para el microservicio Python
        const dailyMap: Record<string, { count: number; revenue: number }> = {};
        for (const b of bookings) {
            const day = b.createdAt.toISOString().split('T')[0]!;
            if (!dailyMap[day]) dailyMap[day] = { count: 0, revenue: 0 };
            dailyMap[day]!.count++;
        }
        const history = Object.entries(dailyMap).map(([date, v]) => ({
            date, count: v.count, revenue: v.count * precioActual, price: precioActual,
        }));

        // Intentar análisis estadístico con el microservicio Python (garden-pricing)
        let analysis: PricingAnalysis | null = null;
        try {
            const resp = await fetch(`${PRICING_SERVICE_URL}/analyze`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    service_type: serviceType,
                    history,
                    precio_actual: precioActual,
                    precio_promedio_zona: zonePrices.avg,
                    precio_min_zona: zonePrices.min,
                    precio_max_zona: zonePrices.max,
                    forecast_days: 7,
                }),
                signal: AbortSignal.timeout(30_000),
            });
            if (resp.ok) {
                analysis = await resp.json() as PricingAnalysis;
                logger.info(`[PRICING JOB] Python OK ${caregiverId} (${analysis.modelo_usado}, ${analysis.confianza})`);
            } else {
                logger.warn(`[PRICING JOB] Python devolvió ${resp.status} para ${caregiverId}`);
            }
        } catch {
            logger.warn(`[PRICING JOB] garden-pricing no disponible para ${caregiverId} — usando fallback Claude`);
        }

        // Decisión final: Claude con análisis Python, o Claude solo como fallback
        let sugerencia: { precioSugerido: number; porcentajeCambio: number; motivo: string; explicacion: string; debeActualizar: boolean; tendencia?: string };
        let modeloUsado: string;
        let confianza: string;
        let tendencia: string;

        if (analysis) {
            sugerencia = await calcularSugerenciaCuidador({
                caregiverId, zona, serviceType, precioActual,
                precioPromedioZona: zonePrices.avg,
                precioMinZona: zonePrices.min,
                precioMaxZona: zonePrices.max,
                analysis,
            });
            modeloUsado = analysis.modelo_usado;
            confianza   = analysis.confianza;
            tendencia   = analysis.tendencia;
        } else {
            const eventosProximos = obtenerFeriadosProximos();
            const claudeResult = await sugerirPrecioParaCuidador({
                caregiverId, zona, serviceType, precioActual,
                precioPromedioZona: zonePrices.avg,
                precioMinZona: zonePrices.min,
                precioMaxZona: zonePrices.max,
                reservas7d, reservas30d, reservas90d,
                diasSinReserva, variacionVsMesAnteriorPct,
                eventosProximos,
            });
            sugerencia  = claudeResult;
            modeloUsado = 'claude';
            confianza   = 'media';
            tendencia   = claudeResult.tendencia;
        }

        if (!sugerencia.debeActualizar) return;

        await prisma.sugerenciaPrecio.create({
            data: {
                caregiverId,
                serviceType,
                precioActual,
                precioSugerido: sugerencia.precioSugerido,
                porcentajeCambio: sugerencia.porcentajeCambio,
                motivo: sugerencia.motivo,
                explicacion: sugerencia.explicacion,
                confianza,
                modeloUsado,
                tendencia,
                status: 'PENDING',
                expiresAt: new Date(now + 48 * 60 * 60 * 1000),
            },
        });

        logger.info(`[PRICING JOB] Sugerencia creada para cuidador ${caregiverId} (${serviceType}): Bs ${precioActual} → Bs ${sugerencia.precioSugerido}`);
    } catch (err) {
        logger.error(`[PRICING JOB] Error generando sugerencia para ${caregiverId}/${serviceType}:`, err);
    }
}

async function obtenerPreciosZona(zona: string, serviceType: 'PASEO' | 'HOSPEDAJE') {
    // pricePerWalk60 es el precio canónico para PASEO (walk30 = walk60 / 2)
    const field = serviceType === 'PASEO' ? 'pricePerWalk60' : 'pricePerDay';
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

    // Obtener IDs de cuidadores en la zona para filtrar reservas correctamente
    const caregiversEnZona = await prisma.caregiverProfile.findMany({
        where: { zone: zona as any, status: 'APPROVED' },
        select: { id: true },
    });
    const caregiverIds = caregiversEnZona.map(c => c.id);

    const [reservas7, reservas7ant] = await Promise.all([
        prisma.booking.count({
            where: {
                caregiverId: { in: caregiverIds },
                serviceType,
                status: { in: ['CONFIRMED', 'IN_PROGRESS', 'COMPLETED'] },
                createdAt: { gte: hace7Dias },
            },
        }),
        prisma.booking.count({
            where: {
                caregiverId: { in: caregiverIds },
                serviceType,
                status: { in: ['CONFIRMED', 'IN_PROGRESS', 'COMPLETED'] },
                createdAt: { gte: hace37Dias, lt: hace7Dias },
            },
        }),
    ]);

    const totalCaregivers = caregiverIds.length; // Ya tenemos el listado de arriba

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
