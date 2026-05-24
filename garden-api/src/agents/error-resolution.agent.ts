/**
 * Agente de resolución automática de errores de la app.
 *
 * Flujo:
 *  1. Recibe el reporte de error de la app Flutter
 *  2. Claude clasifica el tipo y severidad
 *  3. El agente intenta remediación automática según el tipo
 *  4. Devuelve el resultado completo para notificar al admin
 */

import { callClaude } from '../services/claude.service.js';
import { logAgentCall } from '../shared/agent-logger.js';
import prisma from '../config/database.js';
import logger from '../shared/logger.js';

// ── Tipos ──────────────────────────────────────────────────────────────────

export type ErrorSeverity = 'critical' | 'high' | 'medium' | 'low';

export type ErrorType =
  | 'AUTH_SESSION'       // Token expirado, sesión inválida
  | 'FCM_PUSH'           // Fallo en notificaciones push
  | 'NETWORK'            // Sin conexión, timeout
  | 'DATABASE'           // Error de base de datos
  | 'NULL_CRASH'         // Null pointer, cast error, widget crash
  | 'NAVIGATION'         // Error de routing o navegación
  | 'PAYMENT'            // Fallo en flujo de pago
  | 'UPLOAD'             // Error al subir fotos/videos
  | 'UNKNOWN';           // No clasificable

export interface ErrorAnalysis {
  errorType: ErrorType;
  errorTypeLabel: string;   // Nombre legible para el admin
  severity: ErrorSeverity;
  summary: string;          // Descripción corta del error
  canAutoResolve: boolean;  // ¿El agente puede remediarlo automáticamente?
  remediationPlan: string;  // Qué acción tomará o recomienda
}

export interface ResolutionResult {
  analysis: ErrorAnalysis;
  isResolved: boolean;
  actionTaken: string;      // Qué se ejecutó
  resolvedAt: Date | null;
  requiresManualAction: boolean;
  manualActionGuide?: string; // Qué debe hacer el admin si no se resolvió
}

// ── Sistema prompt ─────────────────────────────────────────────────────────

const SYSTEM_PROMPT = `Eres el Agente de Diagnóstico de Errores de GARDEN, una app de servicios para mascotas en Bolivia.

Recibes reportes de errores enviados automáticamente desde la app móvil Flutter.

Tu tarea es analizar el error y devolver SOLO un objeto JSON con esta estructura exacta:
{
  "errorType": "AUTH_SESSION" | "FCM_PUSH" | "NETWORK" | "DATABASE" | "NULL_CRASH" | "NAVIGATION" | "PAYMENT" | "UPLOAD" | "UNKNOWN",
  "errorTypeLabel": "nombre corto legible para el admin (máx 30 chars)",
  "severity": "critical" | "high" | "medium" | "low",
  "summary": "descripción del problema en 1 oración, en español (máx 80 chars)",
  "canAutoResolve": true | false,
  "remediationPlan": "acción concreta en 1 oración (máx 80 chars)"
}

Reglas de severidad:
- critical: la app no puede funcionar, afecta pagos o datos de usuarios
- high: funcionalidad importante rota, múltiples usuarios afectados
- medium: fallo en feature secundario, usuario puede trabajar de otra manera
- low: error de UI, cosmético, no afecta la funcionalidad

Reglas de canAutoResolve:
- true SOLO para: AUTH_SESSION (limpiar tokens caducados), FCM_PUSH (limpiar tokens FCM inválidos), DATABASE (reintentar conexión)
- false para todo lo demás

Responde ÚNICAMENTE con el JSON. Sin texto adicional.`;

// ── Función principal ──────────────────────────────────────────────────────

export async function analyzeAndResolveError(params: {
  error: string;
  stackTrace?: string;
  platform?: string;
  timestamp?: string;
}): Promise<ResolutionResult> {
  const start = Date.now();

  let analysis: ErrorAnalysis;

  // 1 ─ Claude clasifica el error
  try {
    const userMessage = `Error recibido desde la app:
Platform: ${params.platform ?? 'unknown'}
Timestamp: ${params.timestamp ?? new Date().toISOString()}
Error: ${params.error}
${params.stackTrace ? `\nStack trace (primeras 500 chars):\n${params.stackTrace.substring(0, 500)}` : ''}`;

    analysis = await callClaude(SYSTEM_PROMPT, userMessage, 300);
  } catch (claudeErr) {
    logger.warn('[ErrorAgent] Claude classification failed, using fallback', { claudeErr });
    // Fallback si Claude no está disponible
    analysis = {
      errorType: 'UNKNOWN',
      errorTypeLabel: 'Error desconocido',
      severity: 'medium',
      summary: params.error.substring(0, 80),
      canAutoResolve: false,
      remediationPlan: 'Revisión manual requerida',
    };
  }

  // 2 ─ Intentar remediación automática según el tipo
  let isResolved = false;
  let actionTaken = 'Sin acción automática';
  let requiresManualAction = true;
  let manualActionGuide: string | undefined;

  if (analysis.canAutoResolve) {
    const remedResult = await _executeRemediation(analysis.errorType, params.error);
    isResolved = remedResult.success;
    actionTaken = remedResult.actionTaken;
    requiresManualAction = !remedResult.success;
    manualActionGuide = remedResult.manualGuide;
  } else {
    manualActionGuide = _getManualGuide(analysis.errorType, analysis.severity);
  }

  // 3 ─ Audit log
  await logAgentCall({
    agentType: 'ERROR_RESOLUTION',
    action: 'analyzeAndResolveError',
    input: {
      error: params.error.substring(0, 200),
      platform: params.platform,
      errorType: analysis.errorType,
    },
    output: {
      isResolved,
      actionTaken,
      severity: analysis.severity,
    },
    durationMs: Date.now() - start,
    status: 'SUCCESS',
  });

  return {
    analysis,
    isResolved,
    actionTaken,
    resolvedAt: isResolved ? new Date() : null,
    requiresManualAction,
    manualActionGuide,
  };
}

// ── Remediaciones automáticas ──────────────────────────────────────────────

async function _executeRemediation(
  errorType: ErrorType,
  errorMessage: string
): Promise<{ success: boolean; actionTaken: string; manualGuide?: string }> {
  try {
    switch (errorType) {
      case 'AUTH_SESSION':
        return await _remediateAuthSession();

      case 'FCM_PUSH':
        return await _remediateFcmTokens();

      case 'DATABASE':
        return await _remediateDatabase();

      default:
        return {
          success: false,
          actionTaken: 'Tipo de error sin remediación automática disponible',
        };
    }
  } catch (err) {
    logger.error('[ErrorAgent] Remediation failed', { errorType, err });
    return {
      success: false,
      actionTaken: `Remediación falló: ${err instanceof Error ? err.message : String(err)}`,
      manualGuide: 'Revisar logs del servidor para más detalles',
    };
  }
}

/** Limpia refresh tokens expirados de la base de datos */
async function _remediateAuthSession(): Promise<{
  success: boolean;
  actionTaken: string;
  manualGuide?: string;
}> {
  try {
    const cutoff = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000); // 7 días

    // Limpiar refresh tokens viejos (si existe la tabla)
    let deleted = 0;
    try {
      const result = await (prisma as any).refreshToken?.deleteMany({
        where: { createdAt: { lt: cutoff } },
      });
      deleted = result?.count ?? 0;
    } catch {
      // La tabla puede no existir — no es un fallo crítico
    }

    // Invalidar FCM tokens de usuarios inactivos hace más de 30 días
    const inactiveUsers = await prisma.user.updateMany({
      where: {
        updatedAt: { lt: new Date(Date.now() - 30 * 24 * 60 * 60 * 1000) },
        fcmToken: { not: null },
      },
      data: { fcmToken: null },
    });

    return {
      success: true,
      actionTaken: `Limpiados ${deleted} refresh tokens expirados y ${inactiveUsers.count} tokens FCM de usuarios inactivos`,
    };
  } catch (err) {
    return {
      success: false,
      actionTaken: 'Error al limpiar tokens de sesión',
      manualGuide: 'Ejecutar manualmente: DELETE FROM refresh_tokens WHERE created_at < NOW() - INTERVAL 7 DAYS',
    };
  }
}

/** Limpia tokens FCM inválidos detectados por Firebase */
async function _remediateFcmTokens(): Promise<{
  success: boolean;
  actionTaken: string;
  manualGuide?: string;
}> {
  try {
    // Usuarios sin actividad en 60 días: limpiar sus tokens FCM para ahorrar costos
    const result = await prisma.user.updateMany({
      where: {
        fcmToken: { not: null },
        updatedAt: { lt: new Date(Date.now() - 60 * 24 * 60 * 60 * 1000) },
      },
      data: { fcmToken: null },
    });

    return {
      success: true,
      actionTaken: `Limpiados ${result.count} tokens FCM de usuarios sin actividad (>60 días). Los tokens se renovarán automáticamente en el próximo login.`,
    };
  } catch (err) {
    return {
      success: false,
      actionTaken: 'Error al limpiar tokens FCM',
      manualGuide: 'Revisar la consola de Firebase para tokens inválidos',
    };
  }
}

/** Verifica conectividad con la base de datos */
async function _remediateDatabase(): Promise<{
  success: boolean;
  actionTaken: string;
  manualGuide?: string;
}> {
  try {
    // Ping a la base de datos
    await prisma.$queryRaw`SELECT 1`;
    return {
      success: true,
      actionTaken: 'Verificada la conexión a la base de datos — funciona correctamente. El error pudo ser transitorio.',
    };
  } catch (err) {
    return {
      success: false,
      actionTaken: 'La base de datos no responde',
      manualGuide: 'Verificar el estado del servidor PostgreSQL y la variable DATABASE_URL',
    };
  }
}

/** Genera guía de acción manual según tipo y severidad */
function _getManualGuide(errorType: ErrorType, severity: ErrorSeverity): string {
  const guides: Record<ErrorType, string> = {
    NULL_CRASH:
      'Revisar los logs de Crashlytics/Sentry. El error ocurrió en el cliente. Actualizar la app con una corrección de código.',
    NETWORK:
      'Error de red del lado del cliente. Verificar que los endpoints de la API estén disponibles y el SSL sea válido.',
    NAVIGATION:
      'Error de routing en la app. Revisar go_router y rutas en main.dart.',
    PAYMENT:
      'Error crítico en flujo de pago. Revisar logs de pagos e integración con Stripe/QR. Verificar con el usuario afectado.',
    UPLOAD:
      'Error al subir archivos. Verificar Cloudinary/S3 y los límites de tamaño en el servidor.',
    AUTH_SESSION:
      'Error de sesión. Pedir al usuario que cierre sesión y vuelva a ingresar.',
    FCM_PUSH:
      'Error de notificaciones. Verificar la configuración de Firebase y el token FCM del dispositivo.',
    DATABASE:
      'Error de base de datos. Verificar PostgreSQL y la variable DATABASE_URL del servidor.',
    UNKNOWN:
      'Error no clasificado. Revisar los logs completos en Sentry/Crashlytics con el stack trace completo.',
  };

  const urgencyPrefix = severity === 'critical' ? '🔴 URGENTE: ' : severity === 'high' ? '🟠 ' : '';
  return `${urgencyPrefix}${guides[errorType] ?? guides.UNKNOWN}`;
}
