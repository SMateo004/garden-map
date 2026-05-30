-- ─────────────────────────────────────────────────────────────────────────────
-- Migration: unified wallet + service reports + caregiver infractions
-- ─────────────────────────────────────────────────────────────────────────────

-- 1. Unified wallet on User
ALTER TABLE "users"
  ADD COLUMN IF NOT EXISTS "balance"     DECIMAL(10,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS "bankName"    VARCHAR(100),
  ADD COLUMN IF NOT EXISTS "bankAccount" VARCHAR(50),
  ADD COLUMN IF NOT EXISTS "bankHolder"  VARCHAR(100),
  ADD COLUMN IF NOT EXISTS "bankType"    VARCHAR(20);

-- 2. Migrate existing balances to User.balance (sum from both profiles)
UPDATE "users" u
SET "balance" = COALESCE((
  SELECT cp."balance" FROM "caregiver_profiles" cp WHERE cp."userId" = u.id
), 0)
+ COALESCE((
  SELECT cl."balance" FROM "client_profiles" cl WHERE cl."userId" = u.id
), 0);

-- 3. Migrate bank info from caregiver_profiles to users
UPDATE "users" u
SET
  "bankName"    = cp."bankName",
  "bankAccount" = cp."bankAccount",
  "bankHolder"  = cp."bankHolder",
  "bankType"    = cp."bankType"
FROM "caregiver_profiles" cp
WHERE cp."userId" = u.id
  AND cp."bankName" IS NOT NULL;

-- 4. Add walletPaymentAmount to bookings
ALTER TABLE "bookings"
  ADD COLUMN IF NOT EXISTS "walletPaymentAmount" DECIMAL(10,2) NOT NULL DEFAULT 0;

-- 5. Add infractionCount to caregiver_profiles
ALTER TABLE "caregiver_profiles"
  ADD COLUMN IF NOT EXISTS "infractionCount" INTEGER NOT NULL DEFAULT 0;

-- 6. Create service_reports table
CREATE TABLE IF NOT EXISTS "service_reports" (
  "id"           TEXT         NOT NULL,
  "bookingId"    TEXT         NOT NULL,
  "clientId"     TEXT         NOT NULL,
  "reasons"      TEXT[]       NOT NULL DEFAULT '{}',
  "details"      TEXT,
  "status"       TEXT         NOT NULL DEFAULT 'REFUNDED',
  "refundAmount" DECIMAL(10,2),
  "refundedAt"   TIMESTAMPTZ,
  "createdAt"    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  "updatedAt"    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  CONSTRAINT "service_reports_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "service_reports_bookingId_key" UNIQUE ("bookingId"),
  CONSTRAINT "service_reports_bookingId_fkey"
    FOREIGN KEY ("bookingId") REFERENCES "bookings"("id") ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS "service_reports_clientId_idx"  ON "service_reports"("clientId");
CREATE INDEX IF NOT EXISTS "service_reports_bookingId_idx" ON "service_reports"("bookingId");

-- 7. Create caregiver_infractions table
CREATE TABLE IF NOT EXISTS "caregiver_infractions" (
  "id"            TEXT         NOT NULL,
  "caregiverId"   TEXT         NOT NULL,
  "bookingId"     TEXT,
  "type"          TEXT         NOT NULL,
  "fineAmount"    DECIMAL(10,2),
  "bookingAmount" DECIMAL(10,2),
  "reasons"       TEXT[]       NOT NULL DEFAULT '{}',
  "notified"      BOOLEAN      NOT NULL DEFAULT FALSE,
  "createdAt"     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  CONSTRAINT "caregiver_infractions_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "caregiver_infractions_caregiverId_fkey"
    FOREIGN KEY ("caregiverId") REFERENCES "caregiver_profiles"("id") ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS "caregiver_infractions_caregiverId_idx" ON "caregiver_infractions"("caregiverId");
