import { Router, Request, Response } from 'express';
import Stripe from 'stripe';
import { z } from 'zod';
import { stripe, STRIPE_WEBHOOK_SECRET } from '../../config/stripe.js';
import { authMiddleware } from '../../middleware/auth.middleware.js';
import { asyncHandler } from '../../shared/async-handler.js';
import { ForbiddenError } from '../../shared/errors.js';
import * as paymentService from './payment.service.js';

const router = Router();

const verifyPaymentBodySchema = z
  .object({
    qrId: z.string().min(1).optional(),
    bookingId: z.string().uuid().optional(),
    manual: z.boolean().optional(),
  })
  .refine(
    (data) =>
      (data.manual === true && data.bookingId != null) || (data.manual !== true && data.qrId != null),
    {
      message:
        'Para verificación por QR envía { qrId }. Para aprobación manual (admin) envía { bookingId, manual: true }.',
      path: ['manual'],
    }
  );

/**
 * POST /api/payments/verify
 * Verifica pago: por QR (body { qrId }) o aprobación manual por admin (body { bookingId, manual: true }).
 * Returns: { bookingId, status }
 */
router.post(
  '/verify',
  authMiddleware,
  asyncHandler(async (req: Request, res: Response) => {
    const body = verifyPaymentBodySchema.parse(req.body);
    if (body.manual === true && body.bookingId) {
      if (req.user?.role !== 'ADMIN') {
        throw new ForbiddenError('Solo un administrador puede aprobar pagos manualmente');
      }
      const result = await paymentService.verifyPaymentManual(body.bookingId);
      res.json({ success: true, data: result });
      return;
    }
    const result = await paymentService.verifyPaymentByQr(body.qrId!);
    res.json({ success: true, data: result });
  })
);

/**
 * POST /api/payments/create-checkout-session
 * Body: { bookingId, successUrl?, cancelUrl? }
 * Returns: { sessionId, url } — redirect user to url to pay.
 */
router.post(
  '/create-checkout-session',
  authMiddleware,
  asyncHandler(async (req: Request, res: Response) => {
    const userId = req.user!.userId;
    const { bookingId, successUrl, cancelUrl } = req.body as {
      bookingId: string;
      successUrl?: string;
      cancelUrl?: string;
    };
    if (!bookingId) {
      return res.status(400).json({
        success: false,
        error: { code: 'VALIDATION_ERROR', message: 'bookingId es requerido' },
      });
    }
    const { env } = await import('../../config/env.js');
    const success = successUrl ?? `${env.FRONTEND_URL}/bookings/${bookingId}/success`;
    const cancel = cancelUrl ?? `${env.FRONTEND_URL}/bookings/${bookingId}`;
    const result = await paymentService.createCheckoutSession(
      bookingId,
      success,
      cancel,
      userId
    );
    res.json({ success: true, data: result });
  })
);

/** Webhook router: mount under /api/payments/webhook with express.raw() only for this path. */
export const webhookRouter = Router();
webhookRouter.post('/', (req: Request, res: Response) => {
  const rawBody = (req as Request & { rawBody?: Buffer }).rawBody;
  const sig = req.headers['stripe-signature'];
  if (!STRIPE_WEBHOOK_SECRET || !sig || !rawBody) {
    res.status(400).send('Webhook secret or signature missing');
    return;
  }
  if (!stripe) {
    res.status(503).send('Stripe not configured');
    return;
  }
  let event: Stripe.Event;
  try {
    event = stripe.webhooks.constructEvent(rawBody, sig, STRIPE_WEBHOOK_SECRET);
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Unknown error';
    res.status(400).send(`Webhook signature verification failed: ${message}`);
    return;
  }
  if (event.type === 'checkout.session.completed') {
    const session = event.data.object as Stripe.Checkout.Session;
    paymentService
      .handleCheckoutCompleted(session, event.id) // event.id para idempotencia fuerte
      .then(() => res.status(200).send())
      .catch(() => res.status(500).send());
    return;
  }
  res.status(200).send();
});

export default router;
