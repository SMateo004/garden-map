/**
 * Redis client — ioredis.
 *
 * Si REDIS_URL no está configurada, exporta null (safe-by-default).
 * Todos los módulos que consumen Redis deben verificar que el cliente no sea null
 * antes de usarlo, o delegar a la implementación in-memory como fallback.
 */

import { Redis } from 'ioredis';
import logger from '../shared/logger.js';

let _redis: Redis | null = null;

export function getRedisClient(): Redis | null {
  if (_redis) return _redis;

  const url = process.env.REDIS_URL;
  if (!url) return null;

  const client = new Redis(url, {
    maxRetriesPerRequest: 3,
    enableReadyCheck: true,
    lazyConnect: false,
  });

  client.on('connect', () => logger.info('Redis connected'));
  client.on('error', (err: Error) => logger.error('Redis error', { err: err.message }));
  client.on('close', () => logger.warn('Redis connection closed'));

  _redis = client;
  return _redis;
}

export async function shutdownRedis(): Promise<void> {
  try {
    await _redis?.quit();
  } catch (_) { /* silent */ }
}
