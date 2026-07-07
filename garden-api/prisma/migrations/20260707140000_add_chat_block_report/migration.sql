-- Chat safety: block users + report abusive content (App Store 1.2 UGC / Google Play compliance).
-- Applied to the live database via `npx prisma db push` (see project notes on migration drift);
-- this file exists for changelog/documentation consistency with the rest of prisma/migrations.

-- CreateTable
CREATE TABLE "user_blocks" (
    "id" TEXT NOT NULL,
    "blockerId" TEXT NOT NULL,
    "blockedId" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "user_blocks_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "chat_reports" (
    "id" TEXT NOT NULL,
    "bookingId" TEXT NOT NULL,
    "reporterId" TEXT NOT NULL,
    "reportedUserId" TEXT NOT NULL,
    "reason" TEXT NOT NULL,
    "details" TEXT,
    "messagesSnapshot" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'PENDING',
    "adminNotes" TEXT,
    "reviewedByAdminId" TEXT,
    "reviewedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "chat_reports_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "user_blocks_blockerId_idx" ON "user_blocks"("blockerId");

-- CreateIndex
CREATE INDEX "user_blocks_blockedId_idx" ON "user_blocks"("blockedId");

-- CreateIndex
CREATE UNIQUE INDEX "user_blocks_blockerId_blockedId_key" ON "user_blocks"("blockerId", "blockedId");

-- CreateIndex
CREATE INDEX "chat_reports_bookingId_idx" ON "chat_reports"("bookingId");

-- CreateIndex
CREATE INDEX "chat_reports_reporterId_idx" ON "chat_reports"("reporterId");

-- CreateIndex
CREATE INDEX "chat_reports_reportedUserId_idx" ON "chat_reports"("reportedUserId");

-- CreateIndex
CREATE INDEX "chat_reports_status_idx" ON "chat_reports"("status");

-- AddForeignKey
ALTER TABLE "user_blocks" ADD CONSTRAINT "user_blocks_blockerId_fkey" FOREIGN KEY ("blockerId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "user_blocks" ADD CONSTRAINT "user_blocks_blockedId_fkey" FOREIGN KEY ("blockedId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "chat_reports" ADD CONSTRAINT "chat_reports_bookingId_fkey" FOREIGN KEY ("bookingId") REFERENCES "bookings"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "chat_reports" ADD CONSTRAINT "chat_reports_reporterId_fkey" FOREIGN KEY ("reporterId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "chat_reports" ADD CONSTRAINT "chat_reports_reportedUserId_fkey" FOREIGN KEY ("reportedUserId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
