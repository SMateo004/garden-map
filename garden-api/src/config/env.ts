import { z } from 'zod';
import dotenv from 'dotenv';

dotenv.config();

const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'production', 'test']).default('development'),
  PORT: z.string().default('3000'),
  DATABASE_URL: z.string().min(1),
  JWT_SECRET: z.string().min(32),
  JWT_EXPIRES_IN: z.string().default('7d'),
  JWT_REFRESH_SECRET: z.string().min(32).optional(),
  JWT_REFRESH_EXPIRES_IN: z.string().default('30d'),
  CLOUDINARY_CLOUD_NAME: z.string().optional(),
  CLOUDINARY_API_KEY: z.string().optional(),
  CLOUDINARY_API_SECRET: z.string().optional(),
  FRONTEND_URL: z.string().default('http://localhost:5173'),
  API_PUBLIC_URL: z.string().default('http://localhost:3000'),
  ALLOWED_ORIGINS: z.string().default('http://localhost:5173,http://localhost:3000'),
  LOG_LEVEL: z.enum(['error', 'warn', 'info', 'debug']).default('info'),
  // AWS Rekognition (identity verification)
  AWS_ACCESS_KEY_ID: z.string().optional(),
  AWS_SECRET_ACCESS_KEY: z.string().optional(),
  AWS_REGION: z.string().default('us-east-1'),
  AWS_S3_BUCKET: z.string().optional(),
  // Stripe (payments)
  STRIPE_SECRET_KEY: z.string().optional(),
  STRIPE_PUBLISHABLE_KEY: z.string().optional(),
  STRIPE_WEBHOOK_SECRET: z.string().optional(),
  // Email (Resend is the ONLY provider)
  RESEND_API_KEY: z.string().min(1, 'RESEND_API_KEY is required for email delivery'),
  EMAIL_FROM: z.string().min(1, 'EMAIL_FROM is required for email delivery'),
  // Redis (cache + Socket.io adapter)
  REDIS_URL: z.string().url().optional(),
  // Prisma connection pool (appended to DATABASE_URL if not already present)
  DB_POOL_SIZE: z.coerce.number().int().min(1).max(100).default(10),
  DB_POOL_TIMEOUT: z.coerce.number().int().min(1).max(300).default(30),
  // Observabilidad
  SENTRY_DSN: z.string().url().optional(),
  POSTHOG_API_KEY: z.string().optional(),
  // Blockchain (Smart Contracts)
  BLOCKCHAIN_RPC_URL: z.string().optional(),
  BLOCKCHAIN_PRIVATE_KEY: z.string().optional(),
  BLOCKCHAIN_CONTRACT_ADDRESS: z.string().optional(),
  BLOCKCHAIN_PROFILES_ADDRESS: z.string().optional(),
  BLOCKCHAIN_ENABLED: z.string().transform(v => v === 'true').default('false'),
});

const parsed = envSchema.safeParse(process.env);
if (!parsed.success) {
  console.error('Invalid env:', parsed.error.flatten().fieldErrors);
  process.exit(1);
}

export const env = parsed.data;
