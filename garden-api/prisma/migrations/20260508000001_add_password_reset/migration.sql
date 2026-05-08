-- CreateTable
CREATE TABLE IF NOT EXISTS "password_resets" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "tokenHash" TEXT NOT NULL,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "usedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "password_resets_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX IF NOT EXISTS "password_resets_tokenHash_key" ON "password_resets"("tokenHash");

-- CreateIndex
CREATE INDEX IF NOT EXISTS "password_resets_userId_idx" ON "password_resets"("userId");

-- CreateIndex
CREATE INDEX IF NOT EXISTS "password_resets_tokenHash_idx" ON "password_resets"("tokenHash");

-- AddForeignKey (idempotent via DO block)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'password_resets_userId_fkey'
      AND table_name = 'password_resets'
  ) THEN
    ALTER TABLE "password_resets"
      ADD CONSTRAINT "password_resets_userId_fkey"
      FOREIGN KEY ("userId") REFERENCES "users"("id")
      ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
END $$;

-- Enable RLS (consistent with all other tables)
ALTER TABLE "password_resets" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "password_resets" FORCE ROW LEVEL SECURITY;

-- Grant service user full access
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'password_resets'
      AND policyname = 'service_role_all'
  ) THEN
    EXECUTE 'CREATE POLICY "service_role_all" ON "password_resets"
      FOR ALL TO garden_db_w5cg_user USING (true) WITH CHECK (true)';
  END IF;
END $$;
