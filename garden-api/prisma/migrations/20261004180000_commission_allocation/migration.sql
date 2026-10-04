-- CreateTable
CREATE TABLE "commission_allocation_plans" (
    "id" TEXT NOT NULL,
    "effectiveFrom" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "buckets" JSONB NOT NULL,
    "note" TEXT,
    "createdBy" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "commission_allocation_plans_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "commission_bucket_movements" (
    "id" TEXT NOT NULL,
    "bucket" VARCHAR(24) NOT NULL,
    "amount" DECIMAL(12,2) NOT NULL,
    "description" TEXT NOT NULL,
    "occurredAt" TIMESTAMP(3) NOT NULL,
    "bookingId" TEXT,
    "createdBy" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "commission_bucket_movements_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "commission_allocation_plans_effectiveFrom_idx" ON "commission_allocation_plans"("effectiveFrom");

-- CreateIndex
CREATE INDEX "commission_bucket_movements_bucket_occurredAt_idx" ON "commission_bucket_movements"("bucket", "occurredAt");
