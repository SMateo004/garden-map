-- ============================================================
-- Enable Row Level Security (RLS) on all tables
--
-- Strategy:
--   • ENABLE ROW LEVEL SECURITY  → activates RLS on the table
--   • FORCE ROW LEVEL SECURITY   → applies policies even to the
--     table owner (garden_db_w5cg_user) so no user bypasses them
--   • CREATE POLICY "service_role_all" → grants the API service
--     user full access (USING true / WITH CHECK true), because
--     row-level authorization is already enforced in the app layer
--
-- Any other PostgreSQL user that connects directly to the DB
-- will be blocked by default (no matching policy = no rows).
-- ============================================================

-- ── users ────────────────────────────────────────────────────
ALTER TABLE "users" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "users" FORCE ROW LEVEL SECURITY;
CREATE POLICY "service_role_all" ON "users"
  FOR ALL TO garden_db_w5cg_user USING (true) WITH CHECK (true);

-- ── caregiver_profiles ───────────────────────────────────────
ALTER TABLE "caregiver_profiles" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "caregiver_profiles" FORCE ROW LEVEL SECURITY;
CREATE POLICY "service_role_all" ON "caregiver_profiles"
  FOR ALL TO garden_db_w5cg_user USING (true) WITH CHECK (true);

-- ── client_profiles ──────────────────────────────────────────
ALTER TABLE "client_profiles" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "client_profiles" FORCE ROW LEVEL SECURITY;
CREATE POLICY "service_role_all" ON "client_profiles"
  FOR ALL TO garden_db_w5cg_user USING (true) WITH CHECK (true);

-- ── bookings ─────────────────────────────────────────────────
ALTER TABLE "bookings" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "bookings" FORCE ROW LEVEL SECURITY;
CREATE POLICY "service_role_all" ON "bookings"
  FOR ALL TO garden_db_w5cg_user USING (true) WITH CHECK (true);

-- ── wallet_transactions ──────────────────────────────────────
ALTER TABLE "wallet_transactions" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "wallet_transactions" FORCE ROW LEVEL SECURITY;
CREATE POLICY "service_role_all" ON "wallet_transactions"
  FOR ALL TO garden_db_w5cg_user USING (true) WITH CHECK (true);

-- ── reviews ──────────────────────────────────────────────────
ALTER TABLE "reviews" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "reviews" FORCE ROW LEVEL SECURITY;
CREATE POLICY "service_role_all" ON "reviews"
  FOR ALL TO garden_db_w5cg_user USING (true) WITH CHECK (true);

-- ── pets ─────────────────────────────────────────────────────
ALTER TABLE "pets" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "pets" FORCE ROW LEVEL SECURITY;
CREATE POLICY "service_role_all" ON "pets"
  FOR ALL TO garden_db_w5cg_user USING (true) WITH CHECK (true);

-- ── email_verifications ──────────────────────────────────────
ALTER TABLE "email_verifications" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "email_verifications" FORCE ROW LEVEL SECURITY;
CREATE POLICY "service_role_all" ON "email_verifications"
  FOR ALL TO garden_db_w5cg_user USING (true) WITH CHECK (true);

-- ── identity_verification_sessions ───────────────────────────
ALTER TABLE "identity_verification_sessions" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "identity_verification_sessions" FORCE ROW LEVEL SECURITY;
CREATE POLICY "service_role_all" ON "identity_verification_sessions"
  FOR ALL TO garden_db_w5cg_user USING (true) WITH CHECK (true);

-- ── verification_audits ──────────────────────────────────────
ALTER TABLE "verification_audits" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "verification_audits" FORCE ROW LEVEL SECURITY;
CREATE POLICY "service_role_all" ON "verification_audits"
  FOR ALL TO garden_db_w5cg_user USING (true) WITH CHECK (true);

-- ── ChatMessage ──────────────────────────────────────────────
ALTER TABLE "ChatMessage" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "ChatMessage" FORCE ROW LEVEL SECURITY;
CREATE POLICY "service_role_all" ON "ChatMessage"
  FOR ALL TO garden_db_w5cg_user USING (true) WITH CHECK (true);

-- ── Dispute ──────────────────────────────────────────────────
ALTER TABLE "Dispute" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "Dispute" FORCE ROW LEVEL SECURITY;
CREATE POLICY "service_role_all" ON "Dispute"
  FOR ALL TO garden_db_w5cg_user USING (true) WITH CHECK (true);

-- ── gift_codes ───────────────────────────────────────────────
ALTER TABLE "gift_codes" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "gift_codes" FORCE ROW LEVEL SECURITY;
CREATE POLICY "service_role_all" ON "gift_codes"
  FOR ALL TO garden_db_w5cg_user USING (true) WITH CHECK (true);

-- ── MeetAndGreet ─────────────────────────────────────────────
ALTER TABLE "MeetAndGreet" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "MeetAndGreet" FORCE ROW LEVEL SECURITY;
CREATE POLICY "service_role_all" ON "MeetAndGreet"
  FOR ALL TO garden_db_w5cg_user USING (true) WITH CHECK (true);

-- ── notifications ────────────────────────────────────────────
ALTER TABLE "notifications" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "notifications" FORCE ROW LEVEL SECURITY;
CREATE POLICY "service_role_all" ON "notifications"
  FOR ALL TO garden_db_w5cg_user USING (true) WITH CHECK (true);

-- ── admin_notifications ──────────────────────────────────────
ALTER TABLE "admin_notifications" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "admin_notifications" FORCE ROW LEVEL SECURITY;
CREATE POLICY "service_role_all" ON "admin_notifications"
  FOR ALL TO garden_db_w5cg_user USING (true) WITH CHECK (true);

-- ── admin_actions ────────────────────────────────────────────
ALTER TABLE "admin_actions" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "admin_actions" FORCE ROW LEVEL SECURITY;
CREATE POLICY "service_role_all" ON "admin_actions"
  FOR ALL TO garden_db_w5cg_user USING (true) WITH CHECK (true);

-- ── admin_broadcast_notifications ────────────────────────────
ALTER TABLE "admin_broadcast_notifications" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "admin_broadcast_notifications" FORCE ROW LEVEL SECURITY;
CREATE POLICY "service_role_all" ON "admin_broadcast_notifications"
  FOR ALL TO garden_db_w5cg_user USING (true) WITH CHECK (true);

-- ── availability ─────────────────────────────────────────────
ALTER TABLE "availability" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "availability" FORCE ROW LEVEL SECURITY;
CREATE POLICY "service_role_all" ON "availability"
  FOR ALL TO garden_db_w5cg_user USING (true) WITH CHECK (true);

-- ── app_settings ─────────────────────────────────────────────
ALTER TABLE "app_settings" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "app_settings" FORCE ROW LEVEL SECURITY;
CREATE POLICY "service_role_all" ON "app_settings"
  FOR ALL TO garden_db_w5cg_user USING (true) WITH CHECK (true);

-- ── agent_logs ───────────────────────────────────────────────
ALTER TABLE "agent_logs" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "agent_logs" FORCE ROW LEVEL SECURITY;
CREATE POLICY "service_role_all" ON "agent_logs"
  FOR ALL TO garden_db_w5cg_user USING (true) WITH CHECK (true);

-- ── AjustePrecio ─────────────────────────────────────────────
ALTER TABLE "AjustePrecio" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "AjustePrecio" FORCE ROW LEVEL SECURITY;
CREATE POLICY "service_role_all" ON "AjustePrecio"
  FOR ALL TO garden_db_w5cg_user USING (true) WITH CHECK (true);

-- ── SugerenciaPrecio ─────────────────────────────────────────
ALTER TABLE "SugerenciaPrecio" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "SugerenciaPrecio" FORCE ROW LEVEL SECURITY;
CREATE POLICY "service_role_all" ON "SugerenciaPrecio"
  FOR ALL TO garden_db_w5cg_user USING (true) WITH CHECK (true);
