/**
 * Cache interface - Redis V2-ready.
 * In-memory stub for MVP; swap for Redis when scaling.
 * Logger is required lazily to avoid circular dependency with modules that use cache (e.g. caregiver.service).
 */

export interface CacheAdapter {
  get<T>(key: string): Promise<T | null>;
  set(key: string, value: unknown, ttlSeconds?: number): Promise<void>;
  del(key: string): Promise<void>;
}

const memory = new Map<string, { value: unknown; expires?: number }>();

/** Borra todas las claves que empiezan con el prefijo (para invalidar listados). */
export async function delByPrefix(prefix: string): Promise<void> {
  const keysToDelete: string[] = [];
  for (const key of memory.keys()) {
    if (key.startsWith(prefix)) keysToDelete.push(key);
  }
  for (const key of keysToDelete) {
    memory.delete(key);
  }
}

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

// Singleton for app use; replace with Redis client in V2
let cache: CacheAdapter = memoryCache;

export function setCacheAdapter(adapter: CacheAdapter): void {
  cache = adapter;
  void import('./logger.js').then((m) => {
    const log = (m as unknown as { default: { info: (msg: string) => void } }).default;
    log.info('Cache adapter replaced (e.g. Redis)');
  });
}

export function getCache(): CacheAdapter {
  return cache;
}

export const CAREGIVER_LIST_CACHE_TTL = 60; // 1 min
export const CAREGIVER_DETAIL_CACHE_TTL = 120;

export function caregiverListCacheKey(filters: Record<string, string | number>): string {
  return `caregivers:list:${JSON.stringify(filters)}`;
}

export function caregiverDetailCacheKey(id: string): string {
  return `caregivers:detail:${id}`;
}
