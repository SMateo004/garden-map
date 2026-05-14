-- ============================================================
-- Migration: db_audit_cleanup
-- Date: 2026-05-12
-- Purpose: Remove unused/superseded columns and standardize
--          table names to snake_case for consistency and audit.
-- ============================================================

-- -------------------------------------------------------
-- 1. Remove obsolete email verification columns from users.
--    Replaced by the email_verifications table (code+expiry
--    stored hashed with attempt limiting since 2026-03-19).
-- -------------------------------------------------------
ALTER TABLE "users" DROP COLUMN IF EXISTS "emailVerificationCode";
ALTER TABLE "users" DROP COLUMN IF EXISTS "emailVerificationExpires";

-- -------------------------------------------------------
-- 2. Remove superseded document columns from caregiver_profiles.
--    idDocument: replaced by ciAnversoUrl (specific CI front).
--    selfie:     replaced by identity_verification_sessions.selfieUrl.
-- -------------------------------------------------------
ALTER TABLE "caregiver_profiles" DROP COLUMN IF EXISTS "idDocument";
ALTER TABLE "caregiver_profiles" DROP COLUMN IF EXISTS "selfie";

-- -------------------------------------------------------
-- 3. Rename tables to consistent snake_case convention.
--    All other tables already use snake_case via @@map.
-- -------------------------------------------------------
ALTER TABLE "AjustePrecio"    RENAME TO "ajuste_precios";
ALTER TABLE "ChatMessage"     RENAME TO "chat_messages";
ALTER TABLE "MeetAndGreet"    RENAME TO "meet_and_greets";
ALTER TABLE "SugerenciaPrecio" RENAME TO "sugerencia_precios";
