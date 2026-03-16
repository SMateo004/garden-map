import { TimeSlot } from '@prisma/client';

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

    // 1.1 Si enabled es true pero no logramos extraer ningún slot de arriba,
    // es probable que sea legacy data o mal configurado. Asumimos todos habilitados con rangos por defecto.
    if (value.enabled === true) {
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
