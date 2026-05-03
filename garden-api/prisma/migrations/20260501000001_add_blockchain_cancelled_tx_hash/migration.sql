-- AlterTable: Add blockchainCancelledTxHash to bookings
ALTER TABLE "bookings" ADD COLUMN IF NOT EXISTS "blockchainCancelledTxHash" TEXT;
