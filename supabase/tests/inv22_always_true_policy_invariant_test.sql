-- =============================================================================
-- pgTAP: INV-22 Always-True RLS Policy Invariant (Standing CI Gate)
--
-- NOT timestamp-bound. Live pg_policies scan that fails whenever ANY permissive
-- policy with qual=true OR with_check=true is exposed to a client role
-- (public / authenticated / anon) on a tenant-facing table — regardless of which
-- migration introduced it. This is the permanent trip-wire that would have caught
-- the 20260614 (tpl_service_all) and 20260616 (tsq_insert_service) regressions on
-- the feature branch, independent of any single migration's own test.
--
-- service_role-scoped USING(true) is allowed (service_role bypasses RLS anyway).
-- RESTRICTIVE USING(true)/USING(false) is allowed (a RESTRICTIVE policy can only
-- subtract access, never grant it).
-- =============================================================================

BEGIN;
SELECT plan(3);

-- ── 1. No always-true PERMISSIVE policy for client roles on tenant tables ──────
SELECT is(
  (SELECT COUNT(*)::int FROM pg_policies
   WHERE schemaname = 'public'
     AND permissive = 'PERMISSIVE'
     AND (qual = 'true' OR with_check = 'true')
     AND (roles::text[] && ARRAY['public','authenticated','anon']::text[] OR roles::text = '{}')
     AND tablename = ANY (ARRAY[
       'telegram_pending_links','telegram_user_consents','telegram_chat_bindings',
       'telegram_binding_tokens','telegram_evidence_links','telegram_evidence_uploads',
       'telegram_evidence_categories','telegram_evidence_metadata','telegram_status_queries',
       'idempotency_keys','sanction_review_queue','shadow_verdicts',
       'justification_recomputation_signals','justification_submission_tokens',
       'justification_audit_logs','sanction_escalation_log','contractual_financial_snapshot'
     ])),
  0,
  'INV-22: No always-true PERMISSIVE policy exposed to client roles on tenant-facing tables'
);

-- ── 2. spatial_ref_sys carries no tenant data (why its read grant is benign) ───
-- The table is supabase_admin-owned; its grants cannot be revoked by the postgres
-- migration role. It holds only public geodesy reference data — assert it has no
-- organization_id column, proving INV-22 is structurally not at risk here.
SELECT is(
  (SELECT COUNT(*)::int FROM information_schema.columns
   WHERE table_schema = 'public'
     AND table_name = 'spatial_ref_sys'
     AND column_name = 'organization_id'),
  0,
  'INV-22: spatial_ref_sys has no organization_id column (no tenant data to leak)'
);

-- ── 3. RESTRICTIVE deny-all intact on service-only Telegram tables ─────────────
SELECT is(
  (SELECT COUNT(*)::int FROM pg_policies
   WHERE schemaname = 'public'
     AND permissive = 'RESTRICTIVE'
     AND qual = 'false'
     AND policyname IN (
       'deny-all authenticated: telegram_pending_links',
       'deny-all anon: telegram_pending_links',
       'deny-all authenticated: telegram_user_consents'
     )),
  3,
  'INV-22: RESTRICTIVE deny-all policies intact on service-only Telegram tables'
);

SELECT * FROM finish();
ROLLBACK;
