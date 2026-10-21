-- Quién paga la comisión (por cuidador y copia por reserva), Premium y orden del marketplace.
ALTER TABLE "caregiver_profiles" ADD COLUMN "commissionPaidBy" VARCHAR(10) NOT NULL DEFAULT 'CLIENT';
ALTER TABLE "caregiver_profiles" ADD COLUMN "commissionPaidByChangedAt" TIMESTAMP(3);
ALTER TABLE "caregiver_profiles" ADD COLUMN "premiumUntil" TIMESTAMP(3);
ALTER TABLE "caregiver_profiles" ADD COLUMN "premiumReminderSentAt" TIMESTAMP(3);
ALTER TABLE "caregiver_profiles" ADD COLUMN "listingBoost" INTEGER NOT NULL DEFAULT 0;
CREATE INDEX "caregiver_profiles_listingBoost_rating_idx" ON "caregiver_profiles"("listingBoost" DESC, "rating" DESC);
CREATE INDEX "caregiver_profiles_premiumUntil_idx" ON "caregiver_profiles"("premiumUntil");

ALTER TABLE "bookings" ADD COLUMN "commissionPaidBy" VARCHAR(10) NOT NULL DEFAULT 'CLIENT';

CREATE TABLE "premium_purchases" (
    "id" TEXT NOT NULL,
    "caregiverId" TEXT NOT NULL,
    "weeks" INTEGER NOT NULL,
    "amount" DECIMAL(10,2) NOT NULL,
    "status" VARCHAR(30) NOT NULL DEFAULT 'PENDING_PAYMENT',
    "method" VARCHAR(10) NOT NULL,
    "manualPaymentKind" VARCHAR(20),
    "note" VARCHAR(500),
    "qrId" TEXT,
    "qrImageUrl" TEXT,
    "qrExpiresAt" TIMESTAMP(3),
    "sipQrId" TEXT,
    "paymentDeclaredAt" TIMESTAMP(3),
    "paidAt" TIMESTAMP(3),
    "autoApprovedAt" TIMESTAMP(3),
    "reviewedAt" TIMESTAMP(3),
    "reviewOutcome" VARCHAR(20),
    "decidedBy" TEXT,
    "activatedFrom" TIMESTAMP(3),
    "activatedUntil" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "premium_purchases_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "premium_purchases_qrId_key" ON "premium_purchases"("qrId");
CREATE INDEX "premium_purchases_caregiverId_status_idx" ON "premium_purchases"("caregiverId", "status");
CREATE INDEX "premium_purchases_status_qrExpiresAt_idx" ON "premium_purchases"("status", "qrExpiresAt");
ALTER TABLE "premium_purchases" ADD CONSTRAINT "premium_purchases_caregiverId_fkey" FOREIGN KEY ("caregiverId") REFERENCES "caregiver_profiles"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- Libro contable: ingresos por Premium.
ALTER TYPE "LedgerEntrySource" ADD VALUE 'AUTO_PREMIUM';
