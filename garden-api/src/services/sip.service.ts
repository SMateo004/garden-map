/**
 * SIP Service — Integración QR bancario Bolivia (MC4 / SIP)
 *
 * Flujo:
 *  1. getToken()      → obtiene JWT de SIP (válido 4h, cacheado)
 *  2. generateQr()    → genera QR real con imagen Base64
 *  3. disableQr()     → inhabilita QR (cancelaciones / expirados)
 *  4. getStatus()     → consulta estado de transacción (PENDIENTE, PAGADO, etc.)
 *
 * Cuando SIP_ENABLED=false todas las funciones lanzan SipDisabledError
 * y booking.service.ts cae en el placeholder local (sin romper dev/CI).
 */

import { env } from '../config/env.js';
import logger from '../shared/logger.js';
import prisma from '../config/database.js';

// ── Tipos de respuesta SIP ───────────────────────────────────────────────────

interface SipTokenResponse {
  codigo: string;
  mensaje: string;
  objeto: { token: string };
}

export interface SipQrResult {
  imagenQr: string;       // Base64 PNG
  idQr: string;
  fechaVencimiento: string; // dd/mm/yyyy
  bancoDestino: string;
  cuentaDestino: string;
  idTransaccion: string;
}

export interface SipTransactionStatus {
  alias: string;
  estadoActual: 'PENDIENTE' | 'PAGADO' | 'INHABILITADO' | 'ERROR';
  fechaProcesamiento?: string;
  numeroOrdenOriginante?: string;
  monto?: number;
  idQr?: string;
  moneda?: string;
  cuentaCliente?: string;
  nombreCliente?: string;
  documentoCliente?: string;
}

// ── Error sentinel para cuando SIP está deshabilitado ───────────────────────

export class SipDisabledError extends Error {
  constructor() {
    super('SIP_ENABLED=false — usando QR placeholder local');
    this.name = 'SipDisabledError';
  }
}

/**
 * El doc SIP indica explícitamente que el token puede invalidarse en cualquier
 * momento y el banco responde 401 Unauthorized — hay que regenerar el token y
 * reintentar, no tratarlo como un error genérico.
 */
export class SipUnauthorizedError extends Error {
  constructor(path: string) {
    super(`SIP ${path} → 401 Unauthorized (token inválido)`);
    this.name = 'SipUnauthorizedError';
  }
}

// ── Token cache (4h según doc SIP) ──────────────────────────────────────────

let cachedToken: string | null = null;
let tokenExpiresAt: number = 0;
const TOKEN_TTL_MS = 3.5 * 60 * 60 * 1000; // 3.5h (margen de 30min antes de expirar)

// ── Helpers ──────────────────────────────────────────────────────────────────

function assertEnabled(): void {
  if (!env.SIP_ENABLED) throw new SipDisabledError();
}

function baseUrl(): string {
  return env.SIP_API_URL!.replace(/\/$/, '');
}

function formatDate(d: Date): string {
  const dd = String(d.getDate()).padStart(2, '0');
  const mm = String(d.getMonth() + 1).padStart(2, '0');
  const yyyy = d.getFullYear();
  return `${dd}/${mm}/${yyyy}`;
}

async function sipPost<T>(
  path: string,
  body: unknown,
  extraHeaders: Record<string, string> = {}
): Promise<T> {
  const url = `${baseUrl()}${path}`;
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...extraHeaders,
    },
    body: JSON.stringify(body),
  });

  if (res.status === 401) {
    throw new SipUnauthorizedError(path);
  }
  if (!res.ok) {
    const text = await res.text().catch(() => '');
    throw new Error(`SIP ${path} → HTTP ${res.status}: ${text}`);
  }

  return res.json() as Promise<T>;
}

/**
 * Ejecuta una llamada autenticada a SIP; si el token cacheado resultó inválido
 * (401), lo descarta, pide uno nuevo y reintenta UNA vez antes de propagar el error.
 */
async function withTokenRetry<T>(fn: (token: string) => Promise<T>): Promise<T> {
  const token = await getToken();
  try {
    return await fn(token);
  } catch (err) {
    if (!(err instanceof SipUnauthorizedError)) throw err;
    logger.warn('[SIP] Token inválido (401) — regenerando y reintentando una vez');
    cachedToken = null;
    tokenExpiresAt = 0;
    const freshToken = await getToken();
    return fn(freshToken);
  }
}

// ── 1. Obtener / cachear token ───────────────────────────────────────────────

export async function getToken(): Promise<string> {
  assertEnabled();

  if (cachedToken && Date.now() < tokenExpiresAt) {
    return cachedToken;
  }

  const data = await sipPost<SipTokenResponse>(
    '/autenticacion/v1/generarToken',
    { username: env.SIP_USERNAME, password: env.SIP_PASSWORD },
    { apikey: env.SIP_APIKEY! }
  );

  if (data.codigo !== 'OK' || !data.objeto?.token) {
    throw new Error(`SIP getToken error: ${data.mensaje}`);
  }

  cachedToken = data.objeto.token;
  tokenExpiresAt = Date.now() + TOKEN_TTL_MS;
  logger.info('[SIP] Token obtenido y cacheado');
  return cachedToken;
}

// ── 2. Generar QR ────────────────────────────────────────────────────────────

export async function generateQr(
  alias: string,
  monto: number,
  expiresAt: Date,
  callbackUrl: string,
  detalleGlosa: string = 'Pago GARDEN'
): Promise<SipQrResult> {
  assertEnabled();

  // SIP solo acepta granularidad de día (dd/mm/yyyy), no horas/minutos.
  // Usamos la fecha de HOY como fechaVencimiento — es la red de seguridad del banco.
  // La invalidación real a los 15 min la hace nuestro job via disableQr().
  const body = {
    alias,
    callback: callbackUrl,
    detalleGlosa: detalleGlosa.slice(0, 30), // max 30 chars según doc
    monto,
    moneda: 'BOB',
    fechaVencimiento: formatDate(new Date()),  // siempre hoy
    tipoSolicitud: 'API',
    unicoUso: true,
  };

  interface SipGenerateQrResponse {
    codigo: string;
    mensaje: string;
    objeto: SipQrResult;
  }

  const data = await withTokenRetry((token) =>
    sipPost<SipGenerateQrResponse>('/api/v1/generaQr', body, {
      Authorization: `Bearer ${token}`,
      apikeyServicio: env.SIP_APIKEY_SERVICIO!,
    })
  );

  if (data.codigo !== '0000' || !data.objeto) {
    throw new Error(`SIP generateQr error [${data.codigo}]: ${data.mensaje}`);
  }

  logger.info('[SIP] QR generado', { alias, idQr: data.objeto.idQr });
  return data.objeto;
}

// ── 3. Inhabilitar QR ────────────────────────────────────────────────────────

export async function disableQr(alias: string): Promise<void> {
  assertEnabled();

  interface SipDisableResponse { codigo: string; mensaje: string; objeto: null }

  const data = await withTokenRetry((token) =>
    sipPost<SipDisableResponse>('/api/v1/inhabilitarPago', { alias }, {
      Authorization: `Bearer ${token}`,
      apikeyServicio: env.SIP_APIKEY_SERVICIO!,
    })
  );

  if (data.codigo !== '0000') {
    // No tiramos error hard — un QR ya inhabilitado / pagado no debe romper la operación
    logger.warn('[SIP] inhabilitarPago respuesta inesperada', { alias, codigo: data.codigo, mensaje: data.mensaje });
    return;
  }

  logger.info('[SIP] QR inhabilitado', { alias });
}

// ── 4. Estado de transacción ─────────────────────────────────────────────────

export async function getTransactionStatus(alias: string): Promise<SipTransactionStatus> {
  assertEnabled();

  interface SipStatusResponse {
    codigo: string;
    mensaje: string;
    objeto: SipTransactionStatus;
  }

  const data = await withTokenRetry((token) =>
    sipPost<SipStatusResponse>('/api/v1/estadoTransaccion', { alias }, {
      Authorization: `Bearer ${token}`,
      apikeyServicio: env.SIP_APIKEY_SERVICIO!,
    })
  );

  if (data.codigo !== '0000' || !data.objeto) {
    throw new Error(`SIP getTransactionStatus error [${data.codigo}]: ${data.mensaje}`);
  }

  return data.objeto;
}

// ── Alerta a admins cuando SIP falla en producción ──────────────────────────
// Antes esto fallaba en silencio y el sistema mostraba un QR placeholder falso
// al cliente. Ahora, además de bloquear el pago con un error claro, avisamos
// a todos los administradores por email — igual que hace el propio banco
// cuando su callback de confirmación falla.

export async function notifyAdminsSipFailure(context: string, bookingId: string, err: unknown): Promise<void> {
  try {
    const message = err instanceof Error ? err.message : String(err);
    const admins = await prisma.user.findMany({
      where: { role: 'ADMIN' },
      select: { email: true },
    });
    if (admins.length === 0) {
      logger.error('[SIP] Falla crítica sin admins registrados para notificar', { context, bookingId, message });
      return;
    }
    const { sendTransactionalEmail } = await import('../modules/auth/email.service.js');
    const subject = `⚠️ Falla del banco (SIP) — ${context}`;
    const html = `
      <p>La integración bancaria SIP falló al ejecutar <b>${context}</b> para la reserva <b>${bookingId}</b>.</p>
      <p>El pago fue bloqueado (no se mostró un QR falso al cliente). Revisa las credenciales SIP y el estado del servicio del banco.</p>
      <p><b>Error:</b> ${message}</p>
    `;
    await Promise.all(
      admins.map((a) => sendTransactionalEmail(a.email, subject, html).catch((e) =>
        logger.error('[SIP] No se pudo enviar email de alerta a admin', { email: a.email, e })
      ))
    );
  } catch (notifyErr) {
    logger.error('[SIP] Error notificando falla crítica a admins', { context, bookingId, notifyErr });
  }
}
