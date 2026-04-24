import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import path from 'path';
import rateLimit from 'express-rate-limit';
import { env } from './config/env.js';
import { errorHandler } from './shared/error-handler.js';
import prisma from './config/database.js';
import { getRedisClient } from './config/redis.js';
import { maintenanceMiddleware } from './middleware/maintenance.middleware.js';
import caregiverRoutes from './modules/caregiver-service/caregiver.routes.js';
import userRoutes from './modules/user-service/user.routes.js';
import adminRoutes from './modules/admin/admin.routes.js';
import bookingRoutes from './modules/booking-service/booking.routes.js';
import paymentRoutes, { webhookRouter as stripeWebhookRouter } from './modules/payment-service/payment.routes.js';
import authRoutes from './modules/auth/auth.routes.js';
import caregiverProfileRoutes from './modules/caregiver-profile/caregiver-profile.routes.js';
import verificationRoutes from './modules/verification/verification.routes.js';
import clientProfileRoutes from './modules/client-profile/client-profile.routes.js';
import uploadRoutes from './modules/upload/upload.routes.js';
import testRoutes from './modules/auth/test.routes.js';
import notificationRoutes from './modules/notification-service/notification.routes.js';
import agentesRoutes from './modules/agentes/agentes.routes.js';
import chatRoutes from './modules/chat/chat.routes.js';
import walletRoutes from './modules/wallet/wallet.routes.js';
import disputeRoutes from './modules/dispute/dispute.routes.js';
import meetAndGreetRoutes from './modules/meet-and-greet/meet-and-greet.routes.js';

const app = express();

// ── Security headers (helmet 7) ──────────────────────────────────────────
app.use(helmet({
  // CSP: esta API solo devuelve JSON — no necesita política de scripts/estilos.
  // Se deshabilita para no interferir con respuestas JSON.
  contentSecurityPolicy: false,

  // COEP: deshabilitado en APIs puras (rompería clientes cross-origin legítimos)
  crossOriginEmbedderPolicy: false,

  // COOP: same-origin — impide que ventanas externas referencien esta API
  crossOriginOpenerPolicy: { policy: 'same-origin' },

  // CORP: cross-origin — permite que el cliente Flutter web consuma la API
  // y que los /uploads sean embebibles desde la app
  crossOriginResourcePolicy: { policy: 'cross-origin' },

  // X-DNS-Prefetch-Control: off — evita prefetch de DNS no solicitado
  dnsPrefetchControl: { allow: false },

  // X-Frame-Options: DENY — impide que la API sea embebida en un <iframe>
  frameguard: { action: 'deny' },

  // Oculta X-Powered-By (no revelar Express)
  hidePoweredBy: true,

  // HSTS: solo en producción; 2 años, subdomains, preload
  hsts: env.NODE_ENV === 'production'
    ? { maxAge: 63072000, includeSubDomains: true, preload: true }
    : false,

  // X-Download-Options: noopen (IE legacy, pero no cuesta nada)
  ieNoOpen: true,

  // X-Content-Type-Options: nosniff — evita MIME sniffing
  noSniff: true,

  // Origin-Agent-Cluster: ?1 — aísla el proceso del agente por origen
  originAgentCluster: true,

  // X-Permitted-Cross-Domain-Policies: none — bloquea Adobe Flash/Reader
  permittedCrossDomainPolicies: { permittedPolicies: 'none' },

  // Referrer-Policy: no-referrer — no filtra la URL en cabecera Referer
  referrerPolicy: { policy: 'no-referrer' },
}));

// Permissions-Policy — desactiva características del navegador no necesarias
// (helmet 7 no lo incluye de forma nativa)
app.use((_req, res, next) => {
  res.setHeader(
    'Permissions-Policy',
    'accelerometer=(), ambient-light-sensor=(), autoplay=(), battery=(), ' +
    'camera=(), cross-origin-isolated=(), display-capture=(), ' +
    'document-domain=(), encrypted-media=(), execution-while-not-rendered=(), ' +
    'execution-while-out-of-viewport=(), fullscreen=(), geolocation=(), ' +
    'gyroscope=(), keyboard-map=(), magnetometer=(), microphone=(), midi=(), ' +
    'navigation-override=(), payment=(), picture-in-picture=(), ' +
    'publickey-credentials-get=(), screen-wake-lock=(), sync-xhr=(), ' +
    'usb=(), web-share=(), xr-spatial-tracking=()',
  );
  next();
});

// ── CORS ──────────────────────────────────────────────────────────────────
// En producción, solo se permiten los orígenes configurados en ALLOWED_ORIGINS
// (variable de entorno en Render). Las apps móviles nativas (Flutter) no envían
// cabecera Origin, por lo que no se ven afectadas por CORS en absoluto.
// En desarrollo se suman patrones de localhost y red local para poder usar
// el simulador, Postman o el panel web en localhost.
const _explicitOrigins: string[] = [
  ...env.ALLOWED_ORIGINS.split(','),
  ...env.VERCEL_DOMAINS.split(','),
].map(o => o.trim()).filter(Boolean);

// Allow garden-* Vercel deployments (production alias + preview URLs for this project)
const _vercelPreviewPattern = /^https:\/\/garden-[\w-]+\.vercel\.app$/;

const _devPatterns: (RegExp | string)[] = env.NODE_ENV !== 'production'
  ? [
      /^http:\/\/localhost:\d+$/,
      /^http:\/\/127\.0\.0\.1:\d+$/,
      /^http:\/\/192\.168\.\d+\.\d+:\d+$/,  // red local (simulador / dispositivo físico)
    ]
  : [];

app.use(cors({
  origin: (origin, callback) => {
    // Peticiones sin Origin (apps móviles nativas, Postman, curl) → siempre permitidas
    if (!origin) return callback(null, true);

    // Orígenes explícitos configurados vía env
    if (_explicitOrigins.includes(origin)) return callback(null, true);

    // Vercel deployments: garden-*.vercel.app (production alias + previews)
    if (_vercelPreviewPattern.test(origin)) return callback(null, true);

    // Patrones adicionales (solo en desarrollo)
    if (_devPatterns.some(p => (typeof p === 'string' ? p === origin : p.test(origin)))) {
      return callback(null, true);
    }

    callback(new Error(`CORS: origin not allowed — ${origin}`));
  },
  methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
  credentials: true,
}));

// ── Global rate limiter ────────────────────────────────────────────────────
// 200 requests per IP per minute for all endpoints except /health.
// Auth-specific endpoints apply stricter limits on top of this (see auth.routes.ts).
const globalLimiter = rateLimit({
  windowMs: 60 * 1_000,
  max: 200,
  standardHeaders: true,
  legacyHeaders: false,
  skip: (req) => req.path === '/health',
  message: {
    success: false,
    error: {
      code: 'RATE_LIMITED',
      message: 'Demasiadas peticiones. Intenta de nuevo en un minuto.',
    },
  },
});
app.use(globalLimiter);

// ── Maintenance mode ───────────────────────────────────────────────────────
// Checked after global rate limit; returns 503 when maintenanceMode=true.
// /health, /api/admin and Stripe webhooks are always allowed through.
app.use(maintenanceMiddleware);

// Stripe webhook
app.use(
  '/api/payments/webhook',
  express.raw({ type: 'application/json' }),
  (req, _res, next) => {
    (req as express.Request & { rawBody?: Buffer }).rawBody = req.body as Buffer;
    next();
  },
  stripeWebhookRouter
);

app.use(express.json({ limit: '2mb' }));

const uploadsDir = path.join(process.cwd(), 'uploads');
app.use('/uploads', (_req, res, next) => {
  res.set('Cross-Origin-Resource-Policy', 'cross-origin');
  next();
});
app.use('/uploads', express.static(uploadsDir));

/**
 * GET /health — liveness + readiness probe.
 *
 * Render and other platforms hit this endpoint to decide whether to route
 * traffic to this instance.  Returns 200 when all critical services are
 * reachable, 503 when any required service is down.
 *
 * Redis is optional (falls back to in-memory cache) so a Redis failure is
 * flagged but does NOT make the pod unhealthy.
 */
app.get('/health', async (_req, res) => {
  const checks: Record<string, 'ok' | 'error' | 'disabled'> = {};

  // 1. Database — required
  try {
    await prisma.$queryRaw`SELECT 1`;
    checks.db = 'ok';
  } catch {
    checks.db = 'error';
  }

  // 2. Redis — optional (in-memory fallback active when absent)
  try {
    const redis = getRedisClient();
    if (redis) {
      await redis.ping();
      checks.redis = 'ok';
    } else {
      checks.redis = 'disabled'; // Running without Redis — not an error
    }
  } catch {
    checks.redis = 'error'; // Redis configured but unreachable
  }

  const healthy = checks.db === 'ok'; // DB is the only required dependency
  res.status(healthy ? 200 : 503).json({
    success: healthy,
    data: {
      status: healthy ? 'ok' : 'degraded',
      checks,
      version: process.env.npm_package_version ?? 'unknown',
      uptime: Math.floor(process.uptime()),
      timestamp: new Date().toISOString(),
    },
  });
});

app.use('/api/auth', authRoutes);
app.use('/api/caregiver', caregiverProfileRoutes);
app.use('/api/verification', verificationRoutes);
app.use('/api/client', clientProfileRoutes);
app.use('/api/upload', uploadRoutes);
app.use('/api/caregivers', caregiverRoutes);
app.use('/api/users', userRoutes);
app.use('/api/admin', adminRoutes);
app.use('/api/bookings', bookingRoutes);
app.use('/api/payments', paymentRoutes);
app.use('/api/notifications', notificationRoutes);
app.use('/api/test', testRoutes);
app.use('/api/agentes', agentesRoutes);
app.use('/api/chat', chatRoutes);
app.use('/api/wallet', walletRoutes);
app.use('/api/disputes', disputeRoutes);
app.use('/api/meet-and-greet', meetAndGreetRoutes);

/** GET /api/settings — public endpoint, no auth required */
app.get('/api/settings', async (_req, res) => {
  try {
    const settings = await prisma.appSettings.findMany();
    const map: Record<string, unknown> = {};
    for (const s of settings) {
      try { map[s.key] = JSON.parse(s.value); } catch { map[s.key] = s.value; }
    }
    const defaults: Record<string, unknown> = {
      walk30Enabled: false,
      maintenanceMode: false,
      newRegistrationsEnabled: true,
      marketplaceEnabled: true,
      paymentsEnabled: true,
    };
    res.json({ success: true, data: { ...defaults, ...map } });
  } catch (err) {
    res.status(500).json({ success: false, error: { code: 'INTERNAL_ERROR', message: 'Error loading settings' } });
  }
});

// ── Middleware de mantenimiento ────────────────────────────────────────────
import { getBoolSetting, invalidateSetting } from './utils/settings-cache.js';

/** Exportado para compatibilidad con admin.controller (ahora usa invalidateSetting) */
export function invalidateMaintenanceCache() { invalidateSetting('maintenanceMode'); }

app.use(async (req, res, next) => {
  // Rutas siempre accesibles: health, settings públicos, auth, admin
  const bypass = ['/health', '/api/settings', '/api/auth', '/api/admin', '/uploads', '/api/payments/webhook'];
  if (bypass.some(p => req.path.startsWith(p))) return next();

  if (await getBoolSetting('maintenanceMode', false)) {
    return res.status(503).json({
      success: false,
      error: {
        code: 'MAINTENANCE_MODE',
        message: 'El servicio está temporalmente en mantenimiento. Inténtalo en unos minutos.',
      },
    });
  }
  next();
});

app.use(errorHandler);

export default app;
