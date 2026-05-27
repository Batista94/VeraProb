-- =============================================================================
-- Fix: rls_policy_always_true (Supabase linter 0014)
-- =============================================================================
-- REASON:
--   Two policies have WITH CHECK (true) for the `authenticated` role, which
--   allows any authenticated user to INSERT rows with ANY organization_id —
--   a cross-tenant write vector (INV-1, INV-22).
--
--   Affected policies:
--
--   1. sla_audit_ledger "Ledger Insert" (FOR INSERT TO authenticated)
--      WITH CHECK (true) → allows inserting rows into ANY tenant's partition.
--      Dart code uses sla_audit_ledger_v2, NOT this parent table directly.
--      The partitioned parent is written only by SECURITY DEFINER RPCs. Fix:
--      restrict to org_id = JWT app_metadata.org_id (safe — no direct
--      client writes to the parent; partitions enforce their own policies).
--
--   2. system_audit_log "system_audit_log_insert_policy" (FOR INSERT TO authenticated)
--      WITH CHECK (true) → allows inserting audit events for any org.
--      The Dart client DOES insert directly to system_audit_log. Super admins
--      insert with a TARGET org_id (not their own JWT org_id, which is NULL
--      for super admins). Fix: allow super admins unconditionally + restrict
--      regular users to their own JWT org_id.
--
-- INVARIANTS:
--   INV-1  — org_id filter on ALL flows (write path now enforced).
--   INV-2  — RLS uses auth.jwt() -> 'app_metadata' ->> 'org_id' (not auth.uid()).
--   INV-3  — Append-only ledger integrity preserved; no UPDATE/DELETE affected.
--   INV-22 — Tenant-A can no longer write rows into Tenant-B's sla_audit_ledger
--             or system_audit_log partitions.
-- =============================================================================

-- ── 1. sla_audit_ledger "Ledger Insert" ──────────────────────────────────────
-- Current: WITH CHECK (true) — allows cross-tenant inserts.
-- Fix:     restrict INSERT to rows matching the caller's org_id.
-- Note:    USING clause stays unchanged (controls SELECT); only WITH CHECK
--          (controls INSERT/UPDATE) is the vulnerability here.
--          The parent table has no direct client consumers (Dart uses v2);
--          this is a belt-and-suspenders fix to close the policy gap.

DROP POLICY IF EXISTS "Ledger Insert" ON public.sla_audit_ledger;

CREATE POLICY "Ledger Insert"
  ON public.sla_audit_ledger
  FOR INSERT
  TO authenticated
  WITH CHECK (
    -- sla_audit_ledger has no organization_id column; tenant ownership is
    -- derived via contract_id → contracts.organization_id (same pattern as
    -- the existing "Ledger Read" SELECT policy on this table).
    EXISTS (
      SELECT 1
      FROM public.contracts c
      WHERE c.id::text = contract_id
        AND c.organization_id = ((auth.jwt() -> 'app_metadata' ->> 'org_id')::UUID)
    )
  );

-- ── 2. system_audit_log insert policy ────────────────────────────────────────
-- Current: WITH CHECK (true) — allows cross-tenant audit log inserts.
-- Fix:     super admins (app_metadata.super_admin = 'true') write audit events
--          for any org (they target a specific org_id in the INSERT payload).
--          Regular authenticated users may only write for their own org.
-- Context: postgres_system_audit_log_service.dart inserts directly from the
--          Flutter client. Super admins pass organizationId of the target org.

DROP POLICY IF EXISTS "system_audit_log_insert_policy" ON public.system_audit_log;

CREATE POLICY "system_audit_log_insert_policy"
  ON public.system_audit_log
  FOR INSERT
  TO authenticated
  WITH CHECK (
    -- Super admins may audit any org (they supply the target org_id in payload)
    (auth.jwt() -> 'app_metadata' ->> 'super_admin') = 'true'
    OR
    -- Regular users: event must be for their own org
    organization_id = ((auth.jwt() -> 'app_metadata' ->> 'org_id')::UUID)
  );

-- ── Verify (advisory) ─────────────────────────────────────────────────────────
-- SELECT schemaname, tablename, policyname, roles, cmd, qual, with_check
-- FROM pg_policies
-- WHERE schemaname = 'public'
--   AND tablename IN ('sla_audit_ledger', 'system_audit_log')
--   AND cmd = 'INSERT'
-- ORDER BY tablename, policyname;
-- Expected: no policy with with_check = 'true' (literal true)
