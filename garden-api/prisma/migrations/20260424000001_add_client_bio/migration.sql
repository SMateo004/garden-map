-- AlterTable: add bio column to client_profiles
ALTER TABLE "client_profiles" ADD COLUMN IF NOT EXISTS "bio" TEXT;
