/**
 * Access-token blacklist — used to immediately revoke JWTs on logout.
 *
 * Strategy:
 *  - Primary store: Redis SET with TTL = remaining token lifetime.
 *  - Fallback: in-memory Map when Redis is not configured (dev / no-Redis deploys).
 *    The in-memory store sweeps expired entries every 10 minutes so it never
 *    grows unbounded.
 *
 * Usage:
 *   blacklistToken(rawJwt)           — call on logout
 *   isTokenBlacklisted(rawJwt)       — call inside authMiddleware
 */

import { createHash } from 'crypto';
import jwt from 'jsonwebtoken';
import { getRedisClient } from '../config/redis.js';
import logger from '../shared/logger.js';

const REDIS_PREFIX = 'bl:at:';

// ── In-memory fallback ────────────────────────────────────────────────────────
const _memStore = new Map<string, number>(); // hash → expiry (unix ms)

setInterval(() => {
  const now = Date.now();
  for (const [k, exp] of _memStore) {
    if (now > exp) _memStore.delete(k);
  }
}, 10 * 60 * 1000).unref();

function hashToken(raw: string): string {
  return createHash('sha256').update(raw).digest('hex');
}

/**
 * Adds the JWT to the blacklist until it naturally expires.
 * Safe to call even if Redis is down or unconfigured.
 */
export async function blacklistToken(rawToken: string): Promise<void> {
  try {
    const decoded = jwt.decode(rawToken) as { exp?: number } | null;
    const exp = decoded?.exp;
    if (!exp) return; // no-expiry token — nothing to blacklist

    const ttlSeconds = exp - Math.floor(Date.now() / 1000);
    if (ttlSeconds <= 0) return; // already expired — no need to store

    const key = hashToken(rawToken);
    const redis = getRedisClient();

    if (redis) {
      await redis.set(`${REDIS_PREFIX}${key}`, '1', 'EX', ttlSeconds);
    } else {
      _memStore.set(key, Date.now() + ttlSeconds * 1000);
    }
  } catch (err: any) {
    // Never crash on blacklist failure — just log
    logger.warn('[TokenBlacklist] Failed to blacklist token', { error: err.message });
  }
}

/**
 * Returns true if the token has been explicitly revoked (is in the blacklist).
 */
export async function isTokenBlacklisted(rawToken: string): Promise<boolean> {
  try {
    const key = hashToken(rawToken);
    const redis = getRedisClient();

    if (redis) {
      const val = await redis.get(`${REDIS_PREFIX}${key}`);
      return val !== null;
    } else {
      const exp = _memStore.get(key);
      if (!exp) return false;
      if (Date.now() > exp) {
        _memStore.delete(key);
        return false;
      }
      return true;
    }
  } catch (err: any) {
    const redis = getRedisClient();
    if (redis) {
      // Redis IS configured but the check failed (e.g. connection lost).
      // Re-throw so authMiddleware can fail-closed and block the request.
      logger.error('[TokenBlacklist] Redis check failed — re-throwing for fail-closed handling', { error: err.message });
      throw err;
    }
    // Redis not configured → unexpected path; log and fail-open
    logger.warn('[TokenBlacklist] Unexpected error in in-memory check', { error: err.message });
    return false;
  }
}
