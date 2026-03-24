SET client_min_messages TO 'WARNING';

-- =============================================================================
-- Migration: 20260410000002 — Fix RLS role path: top-level → app_metadata
--
-- Problem:
--   Policies introduced in 20260406000001, 20260406000003, and 20260408000002
--   check  auth.jwt() ->> 'role'  (top-level JWT claim).
--   The JWT hook (20260410000001) no longer injects 'role' at the top level
--   because PostgreSQL reserves that claim to set the DB execution role —
--   injecting 'TENANT_ADMIN' caused error 22023 "role does not exist".
--   Application roles now live exclusively in app_metadata.role.
--
-- Fix:
--   Rebuild the affected policies to read
--   auth.jwt() -> 'app_metadata' ->> 'role'
--   which is where the hook writes TENANT_ADMIN / AUDITOR / etc.
--
-- Affected tables:
--   - public.sanction_review_queue   (supersedes 20260408000002 policies)
--   - public.sanction_escalation_log (supersedes 20260406000003 policy)
-- =============================================================================

-- ── sanction_review_queue ─────────────────────────────────────────────────────

DROP POLICY IF EXISTS srq_select_own_org ON public.sanction_review_queue;
CREATE POLICY srq_select_own_org
  ON public.sanction_review_queue
  FOR SELECT
  USING (
    organization_id::text = (auth.jwt() ->> 'organization_id')
    AND (auth.jwt() -> 'app_metadata' ->> 'role') IN ('TENANT_ADMIN', 'AUDITOR')
  );

DROP POLICY IF EXISTS srq_update_own_org ON public.sanction_review_queue;
CREATE POLICY srq_update_own_org
  ON public.sanction_review_queue
  FOR UPDATE
  USING (
    organization_id::text = (auth.jwt() ->> 'organization_id')
    AND (auth.jwt() -> 'app_metadata' ->> 'role') IN ('TENANT_ADMIN', 'AUDITOR')
  );

-- ── sanction_escalation_log ───────────────────────────────────────────────────

DROP POLICY IF EXISTS sel_select_own_org ON public.sanction_escalation_log;
CREATE POLICY sel_select_own_org
  ON public.sanction_escalation_log
  FOR SELECT
  USING (
    organization_id::text = (auth.jwt() ->> 'organization_id')
    AND (auth.jwt() -> 'app_metadata' ->> 'role') IN ('TENANT_ADMIN', 'AUDITOR')
  );
