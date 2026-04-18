/**
 * Cache — Redis cuando REDIS_URL está configurada, in-memory como fallback.
 *
 * Interfaz idéntica en ambos casos: el resto de la app no sabe cuál está activo.
 * delByPrefix usa SCAN en Redis (seguro en producción) y iteración en memoria.
 */

import { getRedisClient } from '../config/redis.js';

export interface CacheAdapter {
  get<T>(key: string): Promise<T | null>;
  set(key: string, value: unknown, ttlSeconds?: number): Promise<void>;
  del(key: string): Promise<void>;
}

// ── In-memory adapter (fallback / tests) ─────────────────────────────────────

const memory = new Map<string, { value: unknown; expires?: number }>();

export const memoryCache: CacheAdapter = {
  async get<T>(key: string): Promise<T | null> {
    const entry = memory.get(key);
    if (!entry) return null;
    if (entry.expires && Date.now() > entry.expires) {
      memory.delete(key);
      return null;
    }
    return entry.value as T;
  },

  async set(key: string, value: unknown, ttlSeconds?: number): Promise<void> {
    memory.set(key, {
      value,
      expires: ttlSeconds ? Date.now() + ttlSeconds * 1000 : undefined,
    });
  },

  async del(key: string): Promise<void> {
    memory.delete(key);
  },
};

// ── Redis adapter ─────────────────────────────────────────────────────────────

function makeRedisCache(): CacheAdapter {
  return {
    async get<T>(key: string): Promise<T | null> {
      const client = getRedisClient();
      if (!client) return null;
      const raw = await client.get(key);
      if (raw === null) return null;
      try {
        return JSON.parse(raw) as T;
      } catch {
        return null;
      }
    },

    async set(key: string, value: unknown, ttlSeconds?: number): Promise<void> {
      const client = getRedisClient();
      if (!client) return;
      const serialized = JSON.stringify(value);
      if (ttlSeconds) {
        await client.setex(key, ttlSeconds, serialized);
      } else {
        await client.set(key, serialized);
      }
    },

    async del(key: string): Promise<void> {
      const client = getRedisClient();
      if (!client) return;
      await client.del(key);
    },
  };
}

// ── delByPrefix ───────────────────────────────────────────────────────────────

/** Borra todas las claves que empiezan con el prefijo. Usa SCAN en Redis. */
export async function delByPrefix(prefix: string): Promise<void> {
  const client = getRedisClient();

  if (client) {
    // SCAN es O(N) pero no bloquea el servidor (a diferencia de KEYS)
    let cursor = '0';
    do {
      const [nextCursor, keys] = await client.scan(cursor, 'MATCH', `${prefix}*`, 'COUNT', 100);
      cursor = nextCursor;
      if (keys.length > 0) {
        await client.del(...keys);
      }
    } while (cursor !== '0');
    return;
  }

  // Fallback in-memory
  const toDelete: string[] = [];
  for (const key of memory.keys()) {
    if (key.startsWith(prefix)) toDelete.push(key);
  }
  for (const key of toDelete) memory.delete(key);
}

// ── Singleton ─────────────────────────────────────────────────────────────────

const redisAdapter = makeRedisCache();

/** Devuelve Redis si está disponible, in-memory si no. */
export function getCache(): CacheAdapter {
  return getRedisClient() ? redisAdapter : memoryCache;
}

/** @deprecated Usar getCache(). Solo para tests o overrides explícitos. */
export function setCacheAdapter(_adapter: CacheAdapter): void {
  // No-op: getCache() elige automáticamente según REDIS_URL
}

// ── TTL constants ─────────────────────────────────────────────────────────────

export const CAREGIVER_LIST_CACHE_TTL = 60;   // 1 min
export const CAREGIVER_DETAIL_CACHE_TTL = 120; // 2 min

export function caregiverListCacheKey(filters: Record<string, string | number>): string {
  return `caregivers:list:${JSON.stringify(filters)}`;
}

export function caregiverDetailCacheKey(id: string): string {
  return `caregivers:detail:${id}`;
}
