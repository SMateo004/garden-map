/**
 * Tests for shared/cache.ts
 * Verifica el comportamiento del adaptador in-memory (fallback sin Redis)
 * y que delByPrefix elimina correctamente las claves con el prefijo dado.
 */

import { memoryCache, delByPrefix, getCache } from '../../src/shared/cache';

// Sin REDIS_URL configurada, getCache() debe devolver el adaptador in-memory
jest.mock('../../src/config/redis', () => ({
  getRedisClient: () => null,
}));

describe('memoryCache', () => {
  beforeEach(() => {
    // Limpiar el estado entre tests usando del en claves conocidas
  });

  it('get devuelve null para clave inexistente', async () => {
    const result = await memoryCache.get('nonexistent-key-xyz');
    expect(result).toBeNull();
  });

  it('set y get recuperan el valor correctamente', async () => {
    await memoryCache.set('test:key1', { name: 'Garden' });
    const result = await memoryCache.get<{ name: string }>('test:key1');
    expect(result).toEqual({ name: 'Garden' });
    await memoryCache.del('test:key1');
  });

  it('set con TTL expira el valor correctamente', async () => {
    // TTL de 0.01 segundos (10ms) para el test
    await memoryCache.set('test:ttl', 'expiring-value', 0.01);

    // Inmediatamente disponible
    const immediate = await memoryCache.get('test:ttl');
    expect(immediate).toBe('expiring-value');

    // Esperar a que expire
    await new Promise((r) => setTimeout(r, 20));
    const expired = await memoryCache.get('test:ttl');
    expect(expired).toBeNull();
  });

  it('del elimina la clave', async () => {
    await memoryCache.set('test:delete-me', 42);
    await memoryCache.del('test:delete-me');
    const result = await memoryCache.get('test:delete-me');
    expect(result).toBeNull();
  });

  it('sobrescribe valores existentes con set', async () => {
    await memoryCache.set('test:overwrite', 'first');
    await memoryCache.set('test:overwrite', 'second');
    const result = await memoryCache.get<string>('test:overwrite');
    expect(result).toBe('second');
    await memoryCache.del('test:overwrite');
  });
});

describe('delByPrefix (in-memory)', () => {
  it('elimina todas las claves que empiezan con el prefijo', async () => {
    await memoryCache.set('caregivers:list:a', 'v1');
    await memoryCache.set('caregivers:list:b', 'v2');
    await memoryCache.set('caregivers:detail:1', 'v3'); // NO debe borrarse

    await delByPrefix('caregivers:list:');

    expect(await memoryCache.get('caregivers:list:a')).toBeNull();
    expect(await memoryCache.get('caregivers:list:b')).toBeNull();
    // La clave con otro prefijo permanece
    const detail = await memoryCache.get('caregivers:detail:1');
    expect(detail).toBe('v3');
    await memoryCache.del('caregivers:detail:1');
  });

  it('no lanza error si no hay claves con el prefijo', async () => {
    await expect(delByPrefix('prefix:that:does:not:exist:')).resolves.not.toThrow();
  });

  it('elimina exactamente las claves del prefijo dado, no más', async () => {
    await memoryCache.set('users:1', 'u1');
    await memoryCache.set('users:2', 'u2');
    await memoryCache.set('user:other', 'u3'); // "user:" ≠ "users:"

    await delByPrefix('users:');

    expect(await memoryCache.get('users:1')).toBeNull();
    expect(await memoryCache.get('users:2')).toBeNull();
    expect(await memoryCache.get<string>('user:other')).toBe('u3');
    await memoryCache.del('user:other');
  });
});

describe('getCache (sin Redis)', () => {
  it('devuelve el adaptador in-memory cuando REDIS_URL no está configurada', () => {
    const cache = getCache();
    expect(cache).toBeDefined();
    expect(typeof cache.get).toBe('function');
    expect(typeof cache.set).toBe('function');
    expect(typeof cache.del).toBe('function');
  });
});
