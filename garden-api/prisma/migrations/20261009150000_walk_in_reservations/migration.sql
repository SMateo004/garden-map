-- CreateEnum
CREATE TYPE "WalkInReservationStatus" AS ENUM ('RESERVED', 'CHECKED_IN', 'COMPLETED', 'CANCELLED');

-- CreateTable
CREATE TABLE "walk_in_reservations" (
    "id" TEXT NOT NULL,
    "caregiverProfileId" TEXT NOT NULL,
    "walkInPetId" TEXT NOT NULL,
    "serviceType" "ServiceType" NOT NULL,
    "startDate" DATE NOT NULL,
    "endDate" DATE NOT NULL,
    "status" "WalkInReservationStatus" NOT NULL DEFAULT 'RESERVED',
    "notes" TEXT,
    "visitId" TEXT,
    "createdByUserId" TEXT NOT NULL,
    "overCapacity" BOOLEAN NOT NULL DEFAULT false,
    "cancelledAt" TIMESTAMP(3),
    "cancelledByUserId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "walk_in_reservations_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "walk_in_reservations_visitId_key" ON "walk_in_reservations"("visitId");

-- CreateIndex
CREATE INDEX "walk_in_reservations_caregiverProfileId_status_startDate_idx" ON "walk_in_reservations"("caregiverProfileId", "status", "startDate");

-- CreateIndex
CREATE INDEX "walk_in_reservations_walkInPetId_idx" ON "walk_in_reservations"("walkInPetId");

-- AddForeignKey
ALTER TABLE "walk_in_reservations" ADD CONSTRAINT "walk_in_reservations_caregiverProfileId_fkey" FOREIGN KEY ("caregiverProfileId") REFERENCES "caregiver_profiles"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "walk_in_reservations" ADD CONSTRAINT "walk_in_reservations_walkInPetId_fkey" FOREIGN KEY ("walkInPetId") REFERENCES "walk_in_pets"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "walk_in_reservations" ADD CONSTRAINT "walk_in_reservations_visitId_fkey" FOREIGN KEY ("visitId") REFERENCES "walk_in_visits"("id") ON DELETE SET NULL ON UPDATE CASCADE;
