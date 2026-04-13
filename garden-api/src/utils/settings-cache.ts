/**
 * Cache de AppSettings con TTL de 30s.
 * Evita consultar la BD en cada petición sin sacrificar la reactividad.
 */
import prisma from '../config/database.js';

const _cache: Record<string, { value: boolean; ts: number }> = {};
const TTL = 30_000; // 30 segundos

export async function getBoolSetting(key: string, defaultValue: boolean): Promise<boolean> {
    const now = Date.now();
    if (_cache[key] && now - _cache[key]!.ts < TTL) return _cache[key]!.value;
    try {
        const setting = await prisma.appSettings.findUnique({ where: { key } });
        const value = setting ? JSON.parse(setting.value) === true : defaultValue;
        _cache[key] = { value, ts: now };
        return value;
    } catch {
        return defaultValue; // Si falla la BD, no bloquear al usuario
    }
}

/** Invalida la entrada de cache de una clave (llamar tras updateSetting). */
export function invalidateSetting(key: string) {
    delete _cache[key];
}
