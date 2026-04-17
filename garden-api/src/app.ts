import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import path from 'path';
import { env } from './config/env.js';
import { errorHandler } from './shared/error-handler.js';
import prisma from './config/database.js';
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

app.use(helmet());

// ── CORS ──────────────────────────────────────────────────────────────────
// En producción, solo se permiten los orígenes configurados en ALLOWED_ORIGINS
// (variable de entorno en Render). Las apps móviles nativas (Flutter) no envían
// cabecera Origin, por lo que no se ven afectadas por CORS en absoluto.
// En desarrollo se suman patrones de localhost y red local para poder usar
// el simulador, Postman o el panel web en localhost.
const _explicitOrigins: string[] = env.ALLOWED_ORIGINS
  .split(',')
  .map(o => o.trim())
  .filter(Boolean);

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

app.get('/health', (_req, res) => {
  res.json({
    success: true,
    data: {
      status: 'ok',
      port: process.env.PORT || 3000,
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
