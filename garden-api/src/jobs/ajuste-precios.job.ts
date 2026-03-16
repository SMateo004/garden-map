import cron from 'node-cron';
import { calcularAjusteDinamico } from '../agents/precios.agent.js';
import prisma from '../config/database.js';
import logger from '../shared/logger.js';

const ZONAS_SANTA_CRUZ = [
    'Equipetrol', 'Las Palmas', 'Plan 3000', 'Norte',
    'Sur', 'Centro', 'Urbarí', 'Villa 1ro de Mayo', 'Urubo'
];

const SERVICIOS = ['hospedaje', 'paseo', 'cuidado_en_casa'];

export function iniciarJobAjustePrecios() {
    // Corre todos los días a las 2am
    cron.schedule('0 2 * * *', async () => {
        logger.info('Iniciando job de ajuste dinámico de precios (Claude AI)...');

        for (const zona of ZONAS_SANTA_CRUZ) {
            for (const servicio of SERVICIOS) {
                try {
                    // Obtener datos reales de la base de datos
                    const datos = await obtenerDatosZona(zona, servicio);
                    const ajuste = await calcularAjusteDinamico(datos);

                    // Guardar en base de datos
                    await prisma.ajustePrecio.upsert({
                        where: {
                            zona_servicio: { zona, servicio }
                        },
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
                            zona,
                            servicio,
                            multiplicador: ajuste.multiplicador,
                            porcentajeAjuste: ajuste.porcentajeAjuste,
                            aplicarDesde: new Date(ajuste.aplicarDesde),
                            aplicarHasta: new Date(ajuste.aplicarHasta),
                            motivo: ajuste.motivo,
                            explicacionParaDueno: ajuste.explicacionParaDueno,
                            cuandoVuelveNormal: ajuste.cuandoVuelveNormal,
                        },
                    });

                } catch (error) {
                    logger.error(`Error procesando ajuste dinámico para ${zona}/${servicio}:`, error);
                }
            }
        }
        logger.info('Job de ajuste dinámico de precios completado.');
    });
}

async function obtenerDatosZona(zona: string, servicio: string) {
    const hoy = new Date();
    const hace30Dias = new Date(hoy.getTime() - 30 * 24 * 60 * 60 * 1000);
    const hace7Dias = new Date(hoy.getTime() - 7 * 24 * 60 * 60 * 1000);

    // Simulación rápida de ocupación. 
    // En producción real, sumaríamos días ocupados vs días disponibles.

    // Para reservasUltimos7Dias:
    // Se requiere tener relacion entre Reserva (Booking) y zona, 
    // por ahora enviamos datos mockeados inteligentes para que Claude decida

    return {
        zona,
        servicio,
        ocupacionUltimos30Dias: 0.65, // calcular real basada en agenda e historiales
        reservasUltimos7Dias: 12,     // mock inicial
        reservasMismoPeriodoMesAnterior: 10,
        eventosProximos: ['Feriado local próximo', 'Día de la Madre'], // Se podría conectar a una API de feriados bolivianos
        fechaConsulta: hoy.toISOString().split('T')[0]!,
    };
}
