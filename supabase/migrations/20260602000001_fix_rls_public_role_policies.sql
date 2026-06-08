-- =============================================================================
-- Migration: Fix RLS Policies Scoped to {public} Role (Supabase linter warning)
-- =============================================================================
--
-- HOSTILE REVIEW (Mandatory Step 0 — QA/Security Lead):
--
-- Exploit Path A — Cross-Tenant Data Read (INV-22):
--   Policies with USING(true) TO public (or no explicit role) apply to ALL
--   PostgreSQL roles including `authenticated`. Any Tenant-A user can SELECT
--   every row from tables with these policies, reading Tenant-B's idempotency
--   keys, binding tokens, recomputation signals, and consent records.
--   Closure: replacing USING(true) with USING(org_id = jwt_claim::uuid) makes
--   the predicate per-row; the query optimizer cannot return rows that fail it.
--
-- Exploit Path B — Cross-Tenant Write Injection (INV-1, INV-22):
--   INSERT policies with WITH CHECK(true) TO public allow any authenticated
--   user to inject rows with an arbitrary organization_id, including a target
--   org's UUID. A forged INSERT to sanction_review_queue or shadow_verdicts
--   with Tenant-B's org_id would pollute their audit trail and financials.
--   Closure: WITH CHECK(organization_id = jwt_claim::uuid) prevents inserting
--   rows that claim an org_id the caller does not own.
--
-- Exploit Path C — Token Invalidation DoS (INV-7):
--   tbt_update_service with USING(true) allows any authenticated user to stamp
--   `used_at_utc` on any binding token by UUID. Since token UUIDs are never
--   truly secret (they travel in URLs), an attacker who observes a token can
--   mark it as used before the legitimate driver, blocking their binding.
--   Closure: dropping the policy removes the authenticated UPDATE path entirely;
--   only service_role (which bypasses RLS) performs this stamp via the
--   consume_telegram_binding_token SECURITY DEFINER RPC.
--
-- Exploit Path D — Recomputation Signal Tampering (INV-3, INV-7):
--   jrs_update_service with USING(true)/WITH CHECK(true) allows any
--   authenticated user to stamp resolved_at_utc on ANY signal, falsely
--   marking reconciliations as complete without actual recomputation.
--   Closure: dropping the policy restricts UPDATE to service_role (bypasses
--   RLS). The inhibition trigger is SECURITY DEFINER and unaffected.
--
-- Exploit Path E — Pending Link Enumeration (INV-22, INV-26):
--   tpl_service_all with USING(true) exposes short_id values of all pending
--   self-link tokens to any authenticated user. An attacker can enumerate
--   tokens and call resolve_telegram_orphan_with_link for another driver,
--   hijacking their orphan evidence resolution (driver_id check in the RPC
--   is the only guard, which only fires after the attacker has the short_id).
--   Closure: replace with RESTRICTIVE deny-all for authenticated; service_role
--   bypasses RLS for all legitimate bot operations.
--
-- INVARIANTS ENFORCED:
--   INV-1  — organization_id filter on ALL authenticated flows.
--   INV-2  — RLS uses auth.jwt() claim paths, NEVER auth.uid().
--   INV-3  — Append-only tables protected; no authenticated UPDATE path remains.
--   INV-22 — Tenant-A cannot read or write any Tenant-B rows.
--   INV-26 — 404/empty-result parity: cross-tenant lookups return zero rows.
-- =============================================================================

SET client_min_messages TO 'WARNING';

-- =============================================================================
-- Migration helper: safe DROP POLICY — no-op when table or policy absent.
-- Dropped at bottom of migration.
-- =============================================================================
CREATE OR REPLACE FUNCTION public._mig_drop_policy(pol_name text, tbl_name text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = tbl_name
  ) THEN
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol_name, tbl_name);
  END IF;
END;
$$;

-- =============================================================================
-- Fix 1: spatial_ref_sys — Supabase linter rls_disabled_in_public warning
-- =============================================================================
-- PostGIS system catalog table. RLS cannot be enabled on it (system-managed).
-- The app never queries it through the client SDK. Revoke all client-role
-- access to stop schema introspection via unauthenticated/authenticated paths.
-- service_role retains access for PostGIS internal operations.
-- Guard: table absent on projects without PostGIS extension — skip gracefully.

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'spatial_ref_sys'
  ) THEN
    EXECUTE 'REVOKE ALL ON TABLE public.spatial_ref_sys FROM anon';
    EXECUTE 'REVOKE ALL ON TABLE public.spatial_ref_sys FROM authenticated';
  END IF;
END;
$$;

-- =============================================================================
-- Fix 2: Drop always-true policies (qual=true, TO public)
--        These grant unrestricted cross-tenant access to ALL rows.
-- =============================================================================

-- ── 2a. idempotency_keys: idempotency_keys_service_all ───────────────────────
--
-- Exploit: USING(true) WITH CHECK(true) FOR ALL TO public means any
-- authenticated user reads every key for every tenant, and can update
-- status/response_body of any user's key, poisoning replay responses.
-- Fix: drop the always-true policy. The three granular user-scoped policies
-- (idempotency_keys_select_own / _insert_own / _update_own) in the original
-- migration are already correct and continue to function. Service operations
-- that need full access use service_role which bypasses RLS.

SELECT public._mig_drop_policy('idempotency_keys_service_all', 'idempotency_keys');

-- ── 2b. telegram_chat_bindings: tcb_service_all ──────────────────────────────
--
-- Exploit: USING(true) WITH CHECK(true) FOR ALL TO public means any
-- authenticated user can INSERT a binding for another org's driver (hijacking
-- their Telegram channel) or UPDATE unbound_at_utc to sever an active binding.
-- Fix: drop the always-true policy. The existing tcb_select_own_org policy
-- handles authenticated reads. All writes (INSERT, UPDATE) are done by the
-- consume_telegram_binding_token SECURITY DEFINER RPC via service_role.

SELECT public._mig_drop_policy('tcb_service_all', 'telegram_chat_bindings');

-- ── 2c. telegram_pending_links: tpl_service_all ──────────────────────────────
--
-- Exploit: tpl_service_all is the ONLY policy on this table. Dropping it
-- leaves RLS enabled with zero policies, meaning no authenticated user gets
-- through (implicit deny-all). We add an EXPLICIT RESTRICTIVE deny-all so
-- future maintainers see clear intent and any accidental permissive policy
-- addition cannot override it. Service_role bypasses RLS for bot operations.
-- The COMMENT on the table already declares: "deny-all: service_role only."

SELECT public._mig_drop_policy('tpl_service_all', 'telegram_pending_links');
SELECT public._mig_drop_policy('deny-all authenticated: telegram_pending_links', 'telegram_pending_links');

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'telegram_pending_links'
  ) THEN
    EXECUTE $q$
      CREATE POLICY "deny-all authenticated: telegram_pending_links"
        ON public.telegram_pending_links
        AS RESTRICTIVE
        FOR ALL
        TO authenticated
        USING (false)
        WITH CHECK (false)
    $q$;
  END IF;
END;
$$;

-- ── 2d. telegram_user_consents: tuc_select_service ───────────────────────────
--
-- Exploit: USING(true) FOR SELECT TO public lets any authenticated user read
-- all LGPD consent records across all chat_ids and all tenants. This table
-- has no organization_id column (consent is chat_id-scoped, written by the
-- Telegram bot). Authenticated users have no legitimate read path for raw
-- consent records; reads happen via SECURITY DEFINER RPCs only.
-- Fix: drop the always-true SELECT policy. No replacement needed for
-- authenticated — the bot reads via service_role. A RESTRICTIVE deny-all is
-- added to express explicit intent and harden against future accidental grants.

SELECT public._mig_drop_policy('tuc_select_service', 'telegram_user_consents');
SELECT public._mig_drop_policy('deny-all authenticated: telegram_user_consents', 'telegram_user_consents');

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'telegram_user_consents'
  ) THEN
    EXECUTE $q$
      CREATE POLICY "deny-all authenticated: telegram_user_consents"
        ON public.telegram_user_consents
        AS RESTRICTIVE
        FOR ALL
        TO authenticated
        USING (false)
        WITH CHECK (false)
    $q$;
  END IF;
END;
$$;

-- ── 2e. telegram_binding_tokens: tbt_update_service ─────────────────────────
--
-- Exploit: USING(true) WITH CHECK(true) FOR UPDATE TO public allows any
-- authenticated user to stamp used_at_utc on any binding token, invalidating
-- it before the legitimate driver uses it (DoS on the binding flow, INV-7).
-- Fix: drop the always-true UPDATE policy. The consume_telegram_binding_token
-- SECURITY DEFINER RPC (run by the webhook via service_role) performs this
-- stamp unconditionally through RLS bypass. No authenticated UPDATE path exists
-- or is needed — the tbt_select_own_org and tbt_insert_operator policies remain.

SELECT public._mig_drop_policy('tbt_update_service', 'telegram_binding_tokens');

-- ── 2f. justification_recomputation_signals: jrs_update_service ──────────────
--
-- Exploit: USING(true) WITH CHECK(true) FOR UPDATE TO public allows any
-- authenticated user to stamp resolved_at_utc on any signal, falsely marking
-- a recomputation as complete without actual Phase 9.8.K processing.
-- Fix: drop the policy. Phase 9.8.K stamps resolved_at_utc using service_role
-- (bypasses RLS). The inhibition trigger is SECURITY DEFINER and also bypasses
-- RLS. No authenticated UPDATE path is required.

SELECT public._mig_drop_policy('jrs_update_service', 'justification_recomputation_signals');

-- ── 2g. justification_submission_tokens: jst_update_service ──────────────────
--
-- Exploit: USING(true) WITH CHECK(true) FOR UPDATE TO public allows any
-- authenticated user to stamp used_at_utc on any submission token, burning
-- a driver's single-use URL before they submit their justification.
-- Fix: drop the policy. use_justification_token is SECURITY DEFINER and
-- performs the UPDATE via service_role (bypasses RLS). No authenticated
-- UPDATE path is required.

SELECT public._mig_drop_policy('jst_update_service', 'justification_submission_tokens');

-- =============================================================================
-- Fix 3a: Drop unrestricted INSERT policies for tables the Dart client
--         does NOT write directly (service_role / Edge Functions only).
--         These policies have WITH CHECK(true) and no org restriction —
--         any authenticated user can insert rows for any tenant.
--         service_role bypasses RLS and remains unaffected by removal.
-- =============================================================================

-- justification_audit_logs: jal_insert_service
-- Written exclusively by the update_justification_status_with_audit
-- SECURITY DEFINER RPC. No direct authenticated INSERT path.
SELECT public._mig_drop_policy('jal_insert_service', 'justification_audit_logs');

-- justification_recomputation_signals: jrs_insert_service
-- Written exclusively by the inhibit_execution_on_justification_approval
-- SECURITY DEFINER trigger. No direct authenticated INSERT path.
SELECT public._mig_drop_policy('jrs_insert_service', 'justification_recomputation_signals');

-- justification_submission_tokens: jst_insert_service
-- The existing jst_insert_operator policy (WITH CHECK org + role) handles
-- all legitimate authenticated INSERTs. jst_insert_service is redundant and
-- leaves an unrestricted INSERT path for any authenticated user.
SELECT public._mig_drop_policy('jst_insert_service', 'justification_submission_tokens');

-- sanction_escalation_log: sel_insert_service
-- Written exclusively by service_role Edge Functions / triggers.
-- No direct authenticated INSERT path.
SELECT public._mig_drop_policy('sel_insert_service', 'sanction_escalation_log');

-- telegram_evidence_categories: tec_insert_service
-- Written exclusively by the Telegram bot Edge Function via service_role.
-- No direct authenticated INSERT path (operators READ via tec_select_own_org).
SELECT public._mig_drop_policy('tec_insert_service', 'telegram_evidence_categories');

-- telegram_evidence_metadata: tem_insert_service
-- Written exclusively by the EXIF-extraction Edge Function via service_role.
-- No direct authenticated INSERT path.
SELECT public._mig_drop_policy('tem_insert_service', 'telegram_evidence_metadata');

-- telegram_status_queries: tsq_insert_service
-- Written exclusively by the /status command Edge Function via service_role.
-- No direct authenticated INSERT path (auditors READ via tsq_select_own_org).
SELECT public._mig_drop_policy('tsq_insert_service', 'telegram_status_queries');

-- telegram_user_consents: tuc_insert_service
-- Written exclusively by the Telegram consent webhook via service_role.
-- No direct authenticated INSERT path. The RESTRICTIVE deny-all added in
-- Fix 2d closes this completely.
SELECT public._mig_drop_policy('tuc_insert_service', 'telegram_user_consents');

-- =============================================================================
-- Fix 3b: Replace unrestricted INSERT policies for tables the Dart client
--         DOES write directly. Drop WITH CHECK(true) and add org-scoped
--         replacement TO authenticated with proper tenant isolation.
-- =============================================================================

-- ── sanction_review_queue: srq_insert_service → srq_insert_authenticated ─────
--
-- The Dart SanctionReviewQueueRepository performs upserts on this table.
-- JWT path: auth.jwt() ->> 'organization_id' (confirmed by existing srq_select
-- and srq_update policies in 20260406000001 and 20260407000000).
-- WITH CHECK must mirror the USING clause of the SELECT/UPDATE policies for
-- consistency and anti-oracle parity (INV-26).

SELECT public._mig_drop_policy('srq_insert_service', 'sanction_review_queue');
SELECT public._mig_drop_policy('srq_insert_authenticated', 'sanction_review_queue');

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'sanction_review_queue'
  ) THEN
    EXECUTE $q$
      CREATE POLICY srq_insert_authenticated
        ON public.sanction_review_queue
        FOR INSERT
        TO authenticated
        WITH CHECK (
          organization_id = (auth.jwt() ->> 'organization_id')::uuid
        )
    $q$;
  END IF;
END;
$$;

-- ── shadow_verdicts: sv_insert_service → sv_insert_authenticated ─────────────
--
-- The Dart ShadowVerdictRepository performs upserts on this table.
-- JWT path: auth.jwt() -> 'app_metadata' ->> 'org_id' (confirmed by existing
-- sv_select_super_admin and sv_update_super_admin policies in
-- 20260601000001_shadow_verdicts.sql).

SELECT public._mig_drop_policy('sv_insert_service', 'shadow_verdicts');
SELECT public._mig_drop_policy('sv_insert_authenticated', 'shadow_verdicts');

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'shadow_verdicts'
  ) THEN
    EXECUTE $q$
      CREATE POLICY sv_insert_authenticated
        ON public.shadow_verdicts
        FOR INSERT
        TO authenticated
        WITH CHECK (
          organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid
        )
    $q$;
  END IF;
END;
$$;

-- ── telegram_evidence_links: tel_insert_service → tel_insert_authenticated ───
--
-- The Dart TelegramEvidenceRepository INSERTs evidence link rows.
-- JWT path: auth.jwt() -> 'app_metadata' ->> 'org_id' (confirmed by the
-- existing tel_select_own_org policy in 20260421000001).

SELECT public._mig_drop_policy('tel_insert_service', 'telegram_evidence_links');
SELECT public._mig_drop_policy('tel_insert_authenticated', 'telegram_evidence_links');

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'telegram_evidence_links'
  ) THEN
    EXECUTE $q$
      CREATE POLICY tel_insert_authenticated
        ON public.telegram_evidence_links
        FOR INSERT
        TO authenticated
        WITH CHECK (
          organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid
        )
    $q$;
  END IF;
END;
$$;

-- ── telegram_evidence_uploads: teu_insert_service → teu_insert_authenticated ─
--
-- The Dart TelegramEvidenceRepository INSERTs upload records.
-- JWT path: auth.jwt() -> 'app_metadata' ->> 'org_id' (confirmed by the
-- existing teu_select_own_org policy in 20260420000001).

SELECT public._mig_drop_policy('teu_insert_service', 'telegram_evidence_uploads');
SELECT public._mig_drop_policy('teu_insert_authenticated', 'telegram_evidence_uploads');

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'telegram_evidence_uploads'
  ) THEN
    EXECUTE $q$
      CREATE POLICY teu_insert_authenticated
        ON public.telegram_evidence_uploads
        FOR INSERT
        TO authenticated
        WITH CHECK (
          organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid
        )
    $q$;
  END IF;
END;
$$;

-- =============================================================================
-- Fix 4: contractual_financial_snapshot — superseded always-true policies
--        OR-dominate org-scoped replacements, leaking all tenants' financials
-- =============================================================================
--
-- The original base schema created "Snapshot Read" (USING true) and "Snapshot
-- Insert" (WITH CHECK true). Subsequent migrations added proper org-scoped
-- replacements ("Snapshot tenant isolation select/insert") but did NOT drop
-- the old policies. In PostgreSQL, multiple permissive RLS policies for the
-- same command are OR-evaluated: (true OR org_check) = true. Result: any
-- authenticated user can SELECT all financial snapshots and INSERT with any
-- organization_id, defeating the org-scoped policies entirely.
--
-- Fix: drop the superseded always-true policies. The org-scoped replacements
-- already in place are sufficient and correct.

SELECT public._mig_drop_policy('Snapshot Read',   'contractual_financial_snapshot');
SELECT public._mig_drop_policy('Snapshot Insert', 'contractual_financial_snapshot');

-- =============================================================================
-- Cleanup migration helper
-- =============================================================================
DROP FUNCTION IF EXISTS public._mig_drop_policy(text, text);

-- =============================================================================
-- Advisory verification queries (run manually to confirm post-migration state)
-- =============================================================================
--
-- 1. Confirm no always-true policies remain for authenticated/public roles:
--
--    SELECT schemaname, tablename, policyname, roles, cmd, qual, with_check
--    FROM pg_policies
--    WHERE schemaname = 'public'
--      AND (qual = 'true' OR with_check = 'true')
--      AND (roles && ARRAY['public','authenticated']::text[]
--           OR roles = '{}')
--    ORDER BY tablename, policyname;
--    -- Expected: zero rows (or only service_role-scoped true policies)
--
-- 2. Confirm spatial_ref_sys has no client-role grants (if PostGIS installed):
--
--    SELECT c.relname, array_to_string(c.relacl, ',') AS acl
--    FROM pg_class c
--    JOIN pg_namespace n ON n.oid = c.relnamespace
--    WHERE n.nspname = 'public' AND c.relname = 'spatial_ref_sys';
--    -- Expected: no 'anon=' or 'authenticated=' in acl
--
-- 3. Confirm replacement INSERT policies are present with org isolation:
--
--    SELECT tablename, policyname, roles, cmd, with_check
--    FROM pg_policies
--    WHERE schemaname = 'public'
--      AND tablename IN (
--        'sanction_review_queue', 'shadow_verdicts',
--        'telegram_evidence_links', 'telegram_evidence_uploads'
--      )
--      AND cmd = 'INSERT'
--    ORDER BY tablename, policyname;
--    -- Expected: each table has exactly one INSERT policy TO authenticated
--    --           with with_check containing the org_id = jwt claim predicate
--
-- 4. Confirm RESTRICTIVE deny-all policies on service-only tables:
--
--    SELECT tablename, policyname, polpermissive
--    FROM pg_policies
--    WHERE schemaname = 'public'
--      AND tablename IN ('telegram_pending_links', 'telegram_user_consents')
--    ORDER BY tablename;
--    -- Expected: RESTRICTIVE policy (polpermissive = false) present on both
