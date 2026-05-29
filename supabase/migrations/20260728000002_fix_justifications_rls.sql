-- =============================================================================
-- Migration: Fix Justifications RLS Policies (BUG FIX)
--
-- REASON:
--   The original RLS policies for contractor_justifications and
--   justification_evidence_uploads checked `auth.jwt() ->> 'role'` (which is
--   always 'authenticated') and compared it to lowercase roles ('admin', 'operator').
--   The application roles live under `auth.jwt() -> 'app_metadata' ->> 'role'`
--   and are uppercase ('TENANT_ADMIN', 'OPERATOR', 'AUDITOR').
--   This prevented Tenant Admins and Operators from inserting/selecting justifications.
--
-- SECURITY INVARIANTS:
--   INV-2: RLS uses app_metadata / organization_id.
--   INV-22: Tenant isolation.
-- =============================================================================

SET client_min_messages TO 'WARNING';

-- ── 1. contractor_justifications ─────────────────────────────────────────────

DROP POLICY IF EXISTS cj_select_own_org ON public.contractor_justifications;
CREATE POLICY cj_select_own_org
  ON public.contractor_justifications
  FOR SELECT
  USING (
    organization_id = ((auth.jwt() -> 'app_metadata' ->> 'org_id')::UUID)
    AND (auth.jwt() -> 'app_metadata' ->> 'role') IN ('TENANT_ADMIN', 'OPERATOR', 'AUDITOR')
  );

DROP POLICY IF EXISTS cj_insert_operator ON public.contractor_justifications;
CREATE POLICY cj_insert_operator
  ON public.contractor_justifications
  FOR INSERT
  WITH CHECK (
    organization_id = ((auth.jwt() -> 'app_metadata' ->> 'org_id')::UUID)
    AND (auth.jwt() -> 'app_metadata' ->> 'role') IN ('TENANT_ADMIN', 'OPERATOR')
  );

DROP POLICY IF EXISTS cj_update_operator ON public.contractor_justifications;
CREATE POLICY cj_update_operator
  ON public.contractor_justifications
  FOR UPDATE
  USING (
    organization_id = ((auth.jwt() -> 'app_metadata' ->> 'org_id')::UUID)
    AND (auth.jwt() -> 'app_metadata' ->> 'role') IN ('TENANT_ADMIN', 'OPERATOR')
  );

-- ── 2. justification_evidence_uploads ────────────────────────────────────────

DROP POLICY IF EXISTS jeu_select_own_org ON public.justification_evidence_uploads;
CREATE POLICY jeu_select_own_org
  ON public.justification_evidence_uploads
  FOR SELECT
  USING (
    organization_id = ((auth.jwt() -> 'app_metadata' ->> 'org_id')::UUID)
    AND (auth.jwt() -> 'app_metadata' ->> 'role') IN ('TENANT_ADMIN', 'OPERATOR', 'AUDITOR')
  );

DROP POLICY IF EXISTS jeu_insert_operator ON public.justification_evidence_uploads;
CREATE POLICY jeu_insert_operator
  ON public.justification_evidence_uploads
  FOR INSERT
  WITH CHECK (
    organization_id = ((auth.jwt() -> 'app_metadata' ->> 'org_id')::UUID)
    AND (auth.jwt() -> 'app_metadata' ->> 'role') IN ('TENANT_ADMIN', 'OPERATOR')
  );

-- ── 3. Hardening Service-Role / Edge-Function Insert Policies ─────────────────
-- Scope cj_insert_service and jeu_insert_service TO service_role explicitly.
-- This prevents authenticated/anon users from abusing the broad WITH CHECK (true) policies.

DROP POLICY IF EXISTS cj_insert_service ON public.contractor_justifications;
CREATE POLICY cj_insert_service
  ON public.contractor_justifications
  FOR INSERT
  TO service_role
  WITH CHECK (true);

DROP POLICY IF EXISTS jeu_insert_service ON public.justification_evidence_uploads;
CREATE POLICY jeu_insert_service
  ON public.justification_evidence_uploads
  FOR INSERT
  TO service_role
  WITH CHECK (true);

-- ── 4. Restore Explicit Table Grants for Client-Facing Internal Views/Tables ────
-- B2B client apps query these tables directly or via security_invoker views.
-- RLS (Row Level Security) is fully enabled on all three tables.

-- Allow client SELECT/INSERT/UPDATE/DELETE on trips_audit (needed for trip view and seeder)
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.trips_audit TO authenticated;

-- Allow client SELECT on shadow_executions (needed for security_invoker v_roi_summary view)
GRANT SELECT ON TABLE public.shadow_executions TO authenticated;

-- Allow client SELECT on telegram_evidence_categories (needed for evidence tag joins)
GRANT SELECT ON TABLE public.telegram_evidence_categories TO authenticated;


