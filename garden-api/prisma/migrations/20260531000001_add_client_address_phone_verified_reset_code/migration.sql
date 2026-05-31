-- AddColumn: detailed address fields to client_profiles
ALTER TABLE "client_profiles" ADD COLUMN IF NOT EXISTS "addressLat" DOUBLE PRECISION;
ALTER TABLE "client_profiles" ADD COLUMN IF NOT EXISTS "addressLng" DOUBLE PRECISION;
ALTER TABLE "client_profiles" ADD COLUMN IF NOT EXISTS "addressStreet" VARCHAR(200);
ALTER TABLE "client_profiles" ADD COLUMN IF NOT EXISTS "addressNumber" VARCHAR(20);
ALTER TABLE "client_profiles" ADD COLUMN IF NOT EXISTS "addressApartment" VARCHAR(50);
ALTER TABLE "client_profiles" ADD COLUMN IF NOT EXISTS "addressCondominio" VARCHAR(100);
ALTER TABLE "client_profiles" ADD COLUMN IF NOT EXISTS "addressReference" VARCHAR(200);
ALTER TABLE "client_profiles" ADD COLUMN IF NOT EXISTS "addressZone" VARCHAR(100);

-- AddColumn: phoneVerified to caregiver_profiles
ALTER TABLE "caregiver_profiles" ADD COLUMN IF NOT EXISTS "phoneVerified" BOOLEAN NOT NULL DEFAULT false;

-- CreateTable: password_reset_codes
CREATE TABLE IF NOT EXISTS "password_reset_codes" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "codeHash" TEXT NOT NULL,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "attempts" INTEGER NOT NULL DEFAULT 0,
    "usedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "password_reset_codes_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "password_reset_codes_userId_idx" ON "password_reset_codes"("userId");

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'password_reset_codes_userId_fkey'
  ) THEN
    ALTER TABLE "password_reset_codes" ADD CONSTRAINT "password_reset_codes_userId_fkey"
      FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
END $$;
