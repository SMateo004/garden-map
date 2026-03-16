import Stripe from 'stripe';
import { env } from './env.js';

export const stripe: Stripe | null =
  env.STRIPE_SECRET_KEY && env.STRIPE_SECRET_KEY.startsWith('sk_')
    ? new Stripe(env.STRIPE_SECRET_KEY, { apiVersion: '2025-02-24.acacia' })
    : null;

export const STRIPE_WEBHOOK_SECRET = env.STRIPE_WEBHOOK_SECRET ?? '';
