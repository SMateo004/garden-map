/*
  Warnings:

  - The values [CANCELLATION_REQUESTED] on the enum `BookingStatus` will be removed. If these variants are still used in the database, this will fail.
  - You are about to drop the column `adminCancellationApproved` on the `bookings` table. All the data in the column will be lost.
  - You are about to drop the column `cancellationRequestReason` on the `bookings` table. All the data in the column will be lost.
  - You are about to drop the column `cancellationRequestedAt` on the `bookings` table. All the data in the column will be lost.
  - A unique constraint covering the columns `[ciNumber]` on the table `caregiver_profiles` will be added. If there are existing duplicate values, this will fail.

*/
-- AlterEnum
BEGIN;
CREATE TYPE "BookingStatus_new" AS ENUM ('PENDING_PAYMENT', 'PAYMENT_PENDING_APPROVAL', 'WAITING_CAREGIVER_APPROVAL', 'CONFIRMED', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED', 'REJECTED_BY_CAREGIVER');
ALTER TABLE "bookings" ALTER COLUMN "status" DROP DEFAULT;
ALTER TABLE "bookings" ALTER COLUMN "status" TYPE "BookingStatus_new" USING ("status"::text::"BookingStatus_new");
ALTER TYPE "BookingStatus" RENAME TO "BookingStatus_old";
ALTER TYPE "BookingStatus_new" RENAME TO "BookingStatus";
DROP TYPE "BookingStatus_old";
ALTER TABLE "bookings" ALTER COLUMN "status" SET DEFAULT 'PENDING_PAYMENT';
COMMIT;

-- AlterEnum
ALTER TYPE "VerificationStatus" ADD VALUE 'REVIEW';

-- DropForeignKey
ALTER TABLE "bookings" DROP CONSTRAINT "bookings_caregiverId_fkey";

-- DropForeignKey
ALTER TABLE "bookings" DROP CONSTRAINT "bookings_clientId_fkey";

-- DropForeignKey
ALTER TABLE "reviews" DROP CONSTRAINT "reviews_bookingId_fkey";

-- DropForeignKey
ALTER TABLE "reviews" DROP CONSTRAINT "reviews_caregiverId_fkey";

-- DropForeignKey
ALTER TABLE "reviews" DROP CONSTRAINT "reviews_clientId_fkey";

-- DropIndex
DROP INDEX "bookings_cancellationRequestedAt_idx";

-- DropIndex
DROP INDEX "identity_verification_sessions_expiresAt_idx";

-- AlterTable
ALTER TABLE "bookings" DROP COLUMN "adminCancellationApproved",
DROP COLUMN "cancellationRequestReason",
DROP COLUMN "cancellationRequestedAt",
ADD COLUMN     "ownerRated" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "ownerRating" INTEGER,
ADD COLUMN     "payoutStatus" TEXT NOT NULL DEFAULT 'PENDING',
ADD COLUMN     "serviceEndPhoto" TEXT,
ADD COLUMN     "serviceEndedAt" TIMESTAMP(3),
ADD COLUMN     "serviceEvents" JSONB,
ADD COLUMN     "serviceStartPhoto" TEXT,
ADD COLUMN     "serviceStartedAt" TIMESTAMP(3),
ADD COLUMN     "serviceTrackingData" JSONB,
ADD COLUMN     "startTime" VARCHAR(5);

-- AlterTable
ALTER TABLE "caregiver_profiles" ADD COLUMN     "balance" DECIMAL(10,2) NOT NULL DEFAULT 0,
ADD COLUMN     "reviewChecklist" JSONB,
ADD COLUMN     "verificationAttempts" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN     "verificationLockUntil" TIMESTAMP(3);

-- AlterTable
ALTER TABLE "identity_verification_sessions" ADD COLUMN     "attemptNumber" INTEGER NOT NULL DEFAULT 1,
ADD COLUMN     "behaviorScore" DOUBLE PRECISION,
ADD COLUMN     "ciBackUrl" TEXT,
ADD COLUMN     "deviceDetails" JSONB,
ADD COLUMN     "deviceFingerprint" VARCHAR(128),
ADD COLUMN     "docScore" DOUBLE PRECISION,
ADD COLUMN     "faceScore" DOUBLE PRECISION,
ADD COLUMN     "fraudFlags" JSONB,
ADD COLUMN     "ipAddress" VARCHAR(45),
ADD COLUMN     "livenessStatus" VARCHAR(20),
ADD COLUMN     "locationData" JSONB,
ADD COLUMN     "ocrScore" DOUBLE PRECISION,
ADD COLUMN     "qualityScore" DOUBLE PRECISION,
ADD COLUMN     "trustScore" DOUBLE PRECISION,
ADD COLUMN     "userAgent" TEXT;

-- CreateTable
CREATE TABLE "verification_audits" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "sessionId" TEXT,
    "action" VARCHAR(50) NOT NULL,
    "status" VARCHAR(20) NOT NULL,
    "ipAddress" VARCHAR(45),
    "deviceFingerprint" VARCHAR(128),
    "trustScore" DOUBLE PRECISION,
    "behaviorScore" DOUBLE PRECISION,
    "fraudFlags" JSONB,
    "notes" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "verification_audits_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "email_verifications" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "codeHash" VARCHAR(64) NOT NULL,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "attempts" INTEGER NOT NULL DEFAULT 0,
    "verified" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "email_verifications_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "notifications" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "title" VARCHAR(200) NOT NULL,
    "message" TEXT NOT NULL,
    "type" VARCHAR(20) NOT NULL,
    "read" BOOLEAN NOT NULL DEFAULT false,
    "readAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "notifications_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "AjustePrecio" (
    "id" TEXT NOT NULL,
    "zona" TEXT NOT NULL,
    "servicio" TEXT NOT NULL,
    "multiplicador" DOUBLE PRECISION NOT NULL,
    "porcentajeAjuste" INTEGER NOT NULL,
    "aplicarDesde" TIMESTAMP(3) NOT NULL,
    "aplicarHasta" TIMESTAMP(3) NOT NULL,
    "motivo" TEXT NOT NULL,
    "explicacionParaDueno" TEXT NOT NULL,
    "cuandoVuelveNormal" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "AjustePrecio_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ChatMessage" (
    "id" TEXT NOT NULL,
    "bookingId" TEXT NOT NULL,
    "senderId" TEXT NOT NULL,
    "senderRole" TEXT NOT NULL,
    "message" TEXT NOT NULL,
    "read" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ChatMessage_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "verification_audits_userId_idx" ON "verification_audits"("userId");

-- CreateIndex
CREATE INDEX "verification_audits_deviceFingerprint_idx" ON "verification_audits"("deviceFingerprint");

-- CreateIndex
CREATE INDEX "email_verifications_userId_idx" ON "email_verifications"("userId");

-- CreateIndex
CREATE INDEX "email_verifications_expiresAt_idx" ON "email_verifications"("expiresAt");

-- CreateIndex
CREATE INDEX "notifications_userId_idx" ON "notifications"("userId");

-- CreateIndex
CREATE INDEX "notifications_userId_read_idx" ON "notifications"("userId", "read");

-- CreateIndex
CREATE UNIQUE INDEX "AjustePrecio_zona_servicio_key" ON "AjustePrecio"("zona", "servicio");

-- CreateIndex
CREATE INDEX "ChatMessage_bookingId_idx" ON "ChatMessage"("bookingId");

-- CreateIndex
CREATE INDEX "ChatMessage_senderId_idx" ON "ChatMessage"("senderId");

-- CreateIndex
CREATE UNIQUE INDEX "caregiver_profiles_ciNumber_key" ON "caregiver_profiles"("ciNumber");

-- CreateIndex
CREATE INDEX "identity_verification_sessions_deviceFingerprint_idx" ON "identity_verification_sessions"("deviceFingerprint");

-- CreateIndex
CREATE INDEX "identity_verification_sessions_ipAddress_idx" ON "identity_verification_sessions"("ipAddress");

-- AddForeignKey
ALTER TABLE "bookings" ADD CONSTRAINT "bookings_caregiverId_fkey" FOREIGN KEY ("caregiverId") REFERENCES "caregiver_profiles"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "bookings" ADD CONSTRAINT "bookings_clientId_fkey" FOREIGN KEY ("clientId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "reviews" ADD CONSTRAINT "reviews_bookingId_fkey" FOREIGN KEY ("bookingId") REFERENCES "bookings"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "reviews" ADD CONSTRAINT "reviews_caregiverId_fkey" FOREIGN KEY ("caregiverId") REFERENCES "caregiver_profiles"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "reviews" ADD CONSTRAINT "reviews_clientId_fkey" FOREIGN KEY ("clientId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "verification_audits" ADD CONSTRAINT "verification_audits_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "email_verifications" ADD CONSTRAINT "email_verifications_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "notifications" ADD CONSTRAINT "notifications_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ChatMessage" ADD CONSTRAINT "ChatMessage_bookingId_fkey" FOREIGN KEY ("bookingId") REFERENCES "bookings"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ChatMessage" ADD CONSTRAINT "ChatMessage_senderId_fkey" FOREIGN KEY ("senderId") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
