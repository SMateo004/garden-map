import { TimeSlot } from '@prisma/client';

/**
 * Feriados nacionales de Bolivia (ISO strings) — ÚNICA fuente de verdad.
 * Antes existían dos copias de esta lista (booking.service.ts y
 * caregiver.service.ts) que divergieron: una tenía Carnaval 2025 el 24-25 de
 * febrero, la otra el 17-18. Eso permitía que el mapa de disponibilidad
 * mostrara un día como libre mientras crear la reserva lo rechazaba (o
 * viceversa), dependiendo de qué endpoint se consultara. Cualquier código
 * que necesite esta lista debe importarla de aquí, nunca declarar su propia
 * copia.
 */
export const BOLIVIA_HOLIDAYS = new Set([
  '2025-01-01', '2025-01-22', '2025-02-24', '2025-02-25', '2025-04-18', '2025-04-19',
  '2025-05-01', '2025-06-19', '2025-06-21', '2025-08-06', '2025-10-12', '2025-11-02',
  '2025-12-25', '2026-01-01', '2026-01-22', '2026-02-16', '2026-02-17', '2026-04-03',
  '2026-04-04', '2026-05-01', '2026-06-11', '2026-06-21', '2026-08-06', '2026-10-12',
  '2026-11-02', '2026-12-25',
]);

export interface PaseoSlot {
    slot: TimeSlot;
    enabled: boolean;
    start?: string;
    end?: string;
}

/** Helper para parsear consistentemente los diferentes formatos de timeBlocks en la DB. */
export function parseTimeBlocks(value: any): PaseoSlot[] {
    if (!value || typeof value !== 'object') return [];

    const slots: PaseoSlot[] = [];

    // 1. Formato Anidado (slots: { morning: { enabled: true, start, end } }) o (morning: { enabled, ... })
    const s = value.slots || value;
    const mappings: Record<string, TimeSlot> = {
        morning: 'MANANA', afternoon: 'TARDE', night: 'NOCHE',
        manana: 'MANANA', tarde: 'TARDE', noche: 'NOCHE'
    };

    const defaults: Record<string, { start: string, end: string }> = {
        morning: { start: '08:00', end: '11:00' },
        afternoon: { start: '13:00', end: '17:00' },
        night: { start: '19:00', end: '22:00' }
    };

    for (const [key, slotVal] of Object.entries(mappings)) {
        const data = s[key];
        if (data && (data.enabled === true || data === true)) {
            const defKey = key === 'manana' ? 'morning' : key === 'tarde' ? 'afternoon' : key === 'noche' ? 'night' : key;
            slots.push({
                slot: slotVal,
                enabled: true,
                start: data.start || defaults[defKey]?.start || '08:00',
                end: data.end || defaults[defKey]?.end || '11:00'
            });
        }
    }

    if (slots.length > 0) return slots;

    // 1.1 Si enabled es true Y no hay configuración de slots en absoluto (legacy data),
    // asumimos todos los bloques habilitados con rangos por defecto.
    // No aplicar si los slots existen pero tienen enabled:false (día configurado pero todo desactivado).
    const hasAnySlotConfig = Object.values(s).some((v) => v !== null && v !== undefined);
    if (value.enabled === true && !hasAnySlotConfig) {
        return [
            { slot: 'MANANA', enabled: true, start: '08:00', end: '11:00' },
            { slot: 'TARDE', enabled: true, start: '13:00', end: '17:00' },
            { slot: 'NOCHE', enabled: true, start: '19:00', end: '22:00' }
        ];
    }

    // 2. Formato Plano (MANANA: true, TARDE: true, ...)
    const upperMappings: Record<string, { slot: TimeSlot, defStart: string, defEnd: string }> = {
        MANANA: { slot: 'MANANA', defStart: '08:00', defEnd: '11:00' },
        TARDE: { slot: 'TARDE', defStart: '13:00', defEnd: '17:00' },
        NOCHE: { slot: 'NOCHE', defStart: '19:00', defEnd: '22:00' }
    };
    for (const [key, cfg] of Object.entries(upperMappings)) {
        if (value[key] === true) {
            slots.push({ slot: cfg.slot, enabled: true, start: cfg.defStart, end: cfg.defEnd });
        }
    }

    return slots;
}
