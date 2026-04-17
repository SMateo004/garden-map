/**
 * Analytics — PostHog server-side.
 *
 * Si POSTHOG_API_KEY no está configurada, todas las llamadas
 * son no-ops silenciosos (safe-by-default para desarrollo local).
 *
 * Uso:
 *   import { track } from '../../shared/analytics.js';
 *   track(userId, 'booking_created', { serviceType, totalAmount });
 */

import { PostHog } from 'posthog-node';
import logger from './logger.js';

let _client: PostHog | null = null;

function getClient(): PostHog | null {
  if (_client) return _client;
  const key = process.env.POSTHOG_API_KEY;
  if (!key) return null;
  _client = new PostHog(key, {
    host: 'https://app.posthog.com',
    flushAt: 20,      // envía en batch de 20 eventos
    flushInterval: 30_000, // o cada 30s
  });
  return _client;
}

/** Registra un evento para un usuario identificado. Fire-and-forget. */
export function track(
  userId: string,
  event: string,
  properties?: Record<string, unknown>,
): void {
  try {
    getClient()?.capture({ distinctId: userId, event, properties });
  } catch (err) {
    // Analytics nunca debe romper el flujo de negocio
    logger.warn('PostHog track error', { event, err });
  }
}

/** Identifica o actualiza propiedades del perfil de un usuario. */
export function identify(
  userId: string,
  properties: Record<string, unknown>,
): void {
  try {
    getClient()?.identify({ distinctId: userId, properties });
  } catch (err) {
    logger.warn('PostHog identify error', { userId, err });
  }
}

/** Llama al shutdown de PostHog en el cierre del proceso (flushea eventos pendientes). */
export async function shutdownAnalytics(): Promise<void> {
  try {
    await _client?.shutdown();
  } catch (_) { /* silent */ }
}
