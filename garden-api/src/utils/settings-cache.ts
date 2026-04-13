/**
 * Cache de AppSettings con TTL de 30s.
 * Evita consultar la BD en cada petición sin sacrificar la reactividad.
 * Soporta boolean, number y string.
 */
import prisma from '../config/database.js';

const _cache: Record<string, { raw: string; ts: number }> = {};
const TTL = 30_000; // 30 segundos

async function _getRaw(key: string): Promise<string | null> {
    const now = Date.now();
    if (_cache[key] && now - _cache[key]!.ts < TTL) return _cache[key]!.raw;
    try {
        const setting = await prisma.appSettings.findUnique({ where: { key } });
        const raw = setting?.value ?? 'null';
        _cache[key] = { raw, ts: now };
        return raw;
    } catch {
        return null;
    }
}

export async function getBoolSetting(key: string, defaultValue: boolean): Promise<boolean> {
    const raw = await _getRaw(key);
    if (raw === null) return defaultValue;
    try { return JSON.parse(raw) === true; } catch { return defaultValue; }
}

export async function getNumericSetting(key: string, defaultValue: number): Promise<number> {
    const raw = await _getRaw(key);
    if (raw === null) return defaultValue;
    try {
        const v = JSON.parse(raw);
        return typeof v === 'number' && isFinite(v) ? v : defaultValue;
    } catch { return defaultValue; }
}

export async function getStringSetting(key: string, defaultValue: string): Promise<string> {
    const raw = await _getRaw(key);
    if (raw === null) return defaultValue;
    try {
        const v = JSON.parse(raw);
        return typeof v === 'string' ? v : defaultValue;
    } catch { return defaultValue; }
}

/** Invalida la entrada de cache de una clave (llamar tras updateSetting). */
export function invalidateSetting(key: string) {
    delete _cache[key];
}
