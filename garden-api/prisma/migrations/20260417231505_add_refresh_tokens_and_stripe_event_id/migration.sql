-- ── RefreshToken table ───────────────────────────────────────────────────────
-- Almacena refresh tokens opacos (SHA-256 hasheados) para renovación de sesión
-- sin necesidad de re-login. Se rotan en cada uso; el logout revoca todos.
-- All DDL is idempotent (IF NOT EXISTS) so re-running is safe.

CREATE TABLE IF NOT EXISTS "refresh_tokens" (
  "id"        TEXT      NOT NULL DEFAULT gen_random_uuid()::text,
  "userId"    TEXT      NOT NULL,
  "tokenHash" TEXT      NOT NULL,
  "expiresAt" TIMESTAMP(3) NOT NULL,
  "revokedAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "refresh_tokens_pkey" PRIMARY KEY ("id")
);

-- Índices
CREATE UNIQUE INDEX IF NOT EXISTS "refresh_tokens_tokenHash_key" ON "refresh_tokens"("tokenHash");
CREATE INDEX IF NOT EXISTS "refresh_tokens_userId_idx"    ON "refresh_tokens"("userId");
CREATE INDEX IF NOT EXISTS "refresh_tokens_tokenHash_idx" ON "refresh_tokens"("tokenHash");

-- FK → users (cascade delete: si se borra el usuario, se borran sus tokens)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'refresh_tokens_userId_fkey'
      AND table_name = 'refresh_tokens'
  ) THEN
    ALTER TABLE "refresh_tokens"
      ADD CONSTRAINT "refresh_tokens_userId_fkey"
      FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
END $$;

-- RLS (coherente con la política global del resto de tablas)
ALTER TABLE "refresh_tokens" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "refresh_tokens" FORCE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'refresh_tokens' AND policyname = 'service_role_all'
  ) THEN
    EXECUTE 'CREATE POLICY "service_role_all" ON "refresh_tokens"
      FOR ALL TO garden_db_w5cg_user USING (true) WITH CHECK (true)';
  END IF;
END $$;

-- ── stripeEventId en bookings ────────────────────────────────────────────────
-- Idempotencia fuerte: un evento Stripe no puede procesarse dos veces,
-- incluso si Stripe reenvía el webhook por timeout.

ALTER TABLE "bookings"
  ADD COLUMN IF NOT EXISTS "stripeEventId" TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS "bookings_stripeEventId_key"
  ON "bookings"("stripeEventId")
  WHERE "stripeEventId" IS NOT NULL;
