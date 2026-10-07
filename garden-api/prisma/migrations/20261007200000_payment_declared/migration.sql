-- AlterTable
ALTER TABLE "bookings" ADD COLUMN "paymentDeclaredAt" TIMESTAMP(3),
ADD COLUMN "paymentAutoApprovedAt" TIMESTAMP(3),
ADD COLUMN "paymentReviewedAt" TIMESTAMP(3),
ADD COLUMN "paymentReviewOutcome" VARCHAR(20),
ADD COLUMN "paymentReviewedBy" TEXT,
ADD COLUMN "paymentExpectedAmount" DECIMAL(10,2),
ADD COLUMN "paymentChargedBackAmount" DECIMAL(10,2),
ADD COLUMN "paymentReviewAlertedAt" TIMESTAMP(3);
