-- Add petCount to bookings (default 1 = single pet, backward-compatible)
ALTER TABLE "bookings" ADD COLUMN IF NOT EXISTS "petCount" INTEGER NOT NULL DEFAULT 1;

-- Create booking_pets table
CREATE TABLE IF NOT EXISTS "booking_pets" (
  "id"           TEXT NOT NULL,
  "bookingId"    TEXT NOT NULL,
  "petId"        TEXT,
  "petIndex"     INTEGER NOT NULL,
  "petName"      VARCHAR(200) NOT NULL,
  "petBreed"     VARCHAR(100),
  "petAge"       INTEGER,
  "petSize"      "PetSize",
  "specialNeeds" TEXT,
  CONSTRAINT "booking_pets_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "booking_pets_bookingId_fkey" FOREIGN KEY ("bookingId")
    REFERENCES "bookings"("id") ON DELETE CASCADE,
  CONSTRAINT "booking_pets_petId_fkey" FOREIGN KEY ("petId")
    REFERENCES "pets"("id") ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS "booking_pets_bookingId_idx" ON "booking_pets"("bookingId");
CREATE INDEX IF NOT EXISTS "booking_pets_petId_idx"    ON "booking_pets"("petId");

-- Backfill: one BookingPet row per existing booking that already has petId
INSERT INTO "booking_pets" ("id", "bookingId", "petId", "petIndex", "petName", "petBreed", "petAge", "petSize", "specialNeeds")
SELECT
  gen_random_uuid()::text,
  b."id",
  b."petId",
  1,
  b."petName",
  b."petBreed",
  b."petAge",
  b."petSize",
  b."specialNeeds"
FROM "bookings" b
WHERE b."petId" IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM "booking_pets" bp WHERE bp."bookingId" = b."id"
  );
