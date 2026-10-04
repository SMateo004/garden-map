-- CreateTable
CREATE TABLE "blockchain_records" (
    "id" TEXT NOT NULL,
    "subjectType" VARCHAR(10) NOT NULL,
    "subjectId" VARCHAR(36) NOT NULL,
    "kind" VARCHAR(12) NOT NULL,
    "dedupeKey" VARCHAR(160) NOT NULL,
    "payload" JSONB,
    "status" VARCHAR(10) NOT NULL DEFAULT 'PENDING',
    "attempts" INTEGER NOT NULL DEFAULT 0,
    "nextAttemptAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "lastError" VARCHAR(500),
    "chainId" INTEGER,
    "contractAddress" VARCHAR(42),
    "txHash" VARCHAR(66),
    "sentAt" TIMESTAMP(3),
    "sentBlock" INTEGER,
    "blockNumber" INTEGER,
    "confirmedAt" TIMESTAMP(3),
    "alertedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "blockchain_records_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "blockchain_records_dedupeKey_key" ON "blockchain_records"("dedupeKey");

-- CreateIndex
CREATE INDEX "blockchain_records_status_nextAttemptAt_idx" ON "blockchain_records"("status", "nextAttemptAt");

-- CreateIndex
CREATE INDEX "blockchain_records_subjectId_idx" ON "blockchain_records"("subjectId");
