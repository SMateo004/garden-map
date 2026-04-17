-- ── RefreshToken table ───────────────────────────────────────────────────────
-- Almacena refresh tokens opacos (SHA-256 hasheados) para renovación de sesión
-- sin necesidad de re-login. Se rotan en cada uso; el logout revoca todos.

CREATE TABLE "refresh_tokens" (
  "id"        TEXT      NOT NULL DEFAULT gen_random_uuid()::text,
  "userId"    TEXT      NOT NULL,
  "tokenHash" TEXT      NOT NULL,
  "expiresAt" TIMESTAMP(3) NOT NULL,
  "revokedAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "refresh_tokens_pkey" PRIMARY KEY ("id")
);

-- Índices
CREATE UNIQUE INDEX "refresh_tokens_tokenHash_key" ON "refresh_tokens"("tokenHash");
CREATE INDEX "refresh_tokens_userId_idx"    ON "refresh_tokens"("userId");
CREATE INDEX "refresh_tokens_tokenHash_idx" ON "refresh_tokens"("tokenHash");

-- FK → users (cascade delete: si se borra el usuario, se borran sus tokens)
ALTER TABLE "refresh_tokens"
  ADD CONSTRAINT "refresh_tokens_userId_fkey"
  FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- RLS (coherente con la política global del resto de tablas)
ALTER TABLE "refresh_tokens" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "refresh_tokens" FORCE ROW LEVEL SECURITY;
CREATE POLICY "service_role_all" ON "refresh_tokens"
  FOR ALL TO garden_db_w5cg_user USING (true) WITH CHECK (true);

-- ── stripeEventId en bookings ────────────────────────────────────────────────
-- Idempotencia fuerte: un evento Stripe no puede procesarse dos veces,
-- incluso si Stripe reenvía el webhook por timeout.

ALTER TABLE "bookings"
  ADD COLUMN IF NOT EXISTS "stripeEventId" TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS "bookings_stripeEventId_key"
  ON "bookings"("stripeEventId")
  WHERE "stripeEventId" IS NOT NULL;
