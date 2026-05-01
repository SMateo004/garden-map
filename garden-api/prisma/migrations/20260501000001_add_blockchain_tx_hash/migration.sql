-- AlterTable: track on-chain sync status per user
ALTER TABLE "users" ADD COLUMN "blockchain_tx_hash" TEXT;
