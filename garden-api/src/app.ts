import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import path from 'path';
import { env } from './config/env.js';
import { errorHandler } from './shared/error-handler.js';
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

const app = express();

app.use(helmet());
app.use(cors({
  origin: [/http:\/\/localhost:\d+/, /http:\/\/127\.0\.0\.1:\d+/, 'http://localhost:5173'],
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

app.use(errorHandler);

export default app;
