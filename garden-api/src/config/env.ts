import { z } from 'zod';
import dotenv from 'dotenv';

dotenv.config();

const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'production', 'test']).default('development'),
  PORT: z.string().default('3000'),
  DATABASE_URL: z.string().min(1),
  JWT_SECRET: z.string().min(32),
  JWT_EXPIRES_IN: z.string().default('7d'),
  JWT_REFRESH_SECRET: z.string().min(32),
  JWT_REFRESH_EXPIRES_IN: z.string().default('30d'),
  CLOUDINARY_CLOUD_NAME: z.string().optional(),
  CLOUDINARY_API_KEY: z.string().optional(),
  CLOUDINARY_API_SECRET: z.string().optional(),
  FRONTEND_URL: z.string().default('http://localhost:5173'),
  API_PUBLIC_URL: z.string().default('http://localhost:3000'),
  ALLOWED_ORIGINS: z.string().default('http://localhost:5173,http://localhost:3000'),
  // Vercel deployment domains — comma-separated, supports exact or *.vercel.app suffix
  VERCEL_DOMAINS: z.string().default(''),
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
  // AI Agent (Anthropic — required when BLOCKCHAIN_ENABLED or dispute resolution is active)
  ANTHROPIC_API_KEY: z.string().optional(),
  // Twilio Verify (SMS OTP para verificación de teléfono)
  TWILIO_ACCOUNT_SID: z.string().optional(),
  TWILIO_AUTH_TOKEN: z.string().optional(),
  TWILIO_VERIFY_SERVICE_SID: z.string().optional(),
  // SIP — Integración QR bancario Bolivia (MC4 / Banco)
  // Poner SIP_ENABLED=true y completar las demás vars cuando lleguen las credenciales del banco.
  SIP_ENABLED: z.string().transform(v => v === 'true').default('false'),
  SIP_API_URL: z.string().url().optional(),          // ej. https://sip.mc4.com.bo:8443
  SIP_APIKEY: z.string().optional(),                 // apikey global (del correo del banco)
  SIP_USERNAME: z.string().optional(),               // usuario (del correo del banco)
  SIP_PASSWORD: z.string().optional(),               // contraseña (del correo del banco)
  SIP_APIKEY_SERVICIO: z.string().optional(),        // apikey del servicio (desde portal SIP → Servicios → Mostrar apikey)
  SIP_CALLBACK_USER: z.string().optional(),          // usuario Basic Auth que nosotros definimos para el callback
  SIP_CALLBACK_PASS: z.string().optional(),          // contraseña Basic Auth (debe tener mayúscula + especial)
})
.refine(
  data => data.NODE_ENV !== 'production' || !!data.ANTHROPIC_API_KEY,
  { message: 'ANTHROPIC_API_KEY is required in production', path: ['ANTHROPIC_API_KEY'] }
);

const parsed = envSchema.safeParse(process.env);
if (!parsed.success) {
  console.error('Invalid env:', parsed.error.flatten().fieldErrors);
  process.exit(1);
}

export const env = parsed.data;
