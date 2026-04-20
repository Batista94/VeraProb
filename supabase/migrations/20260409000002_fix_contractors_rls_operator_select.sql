-- =============================================================================
-- Migration: 20260409000002 — Fix contractors RLS: OPERATOR SELECT access
-- =============================================================================
--
-- Problem (AUDIT 4 — LGPD PII Masking failure):
--   "contractors_internal_roles" was a single FOR ALL policy with USING:
--     organization_id = jwt.organization_id AND contractor_id IS NULL
--
--   The contractor_id IS NULL guard fails for OPERATOR in edge cases:
--   - When jwt.app_metadata is absent (JWT hook not yet applied)
--   - When PostgreSQL evaluates JSONB null vs SQL null differently across versions
--   Result: 0 rows returned (PGRST116) even though org_id matches.
--
-- Fix:
--   Split into two explicit policies:
--   1. SELECT  — uses (app_metadata.role IN ...) which is set reliably by hook
--   2. WRITE   — TENANT_ADMIN only (INSERT/UPDATE/DELETE), keeps org guard
--   3. Keep    — contractors_contractor_viewer_isolation unchanged (dual-key INV-20)
--
-- Security audit (INV-20):
--   OPERATOR:           SELECT all org contractors (read-only)     ✓ unchanged
--   TENANT_ADMIN:       Full CRUD                                   ✓ unchanged
--   AUDITOR:            SELECT only (write removed — correct)       ✓ tightened
--   CONTRACTOR_VIEWER:  SELECT own record via dual-key policy        ✓ unchanged
-- =============================================================================

BEGIN;

-- Remove the combined FOR ALL policy whose IS NULL guard blocked OPERATOR SELECT
DROP POLICY IF EXISTS "contractors_internal_roles" ON public.contractors;

-- ── Policy 1: SELECT for internal roles ─────────────────────────────────────
-- Explicit role check replaces the fragile contractor_id IS NULL guard.
-- CONTRACTOR_VIEWER is intentionally NOT in this list — handled by policy 3.
CREATE POLICY "contractors_select_internal"
  ON public.contractors
  FOR SELECT
  TO authenticated
  USING (
    organization_id = (auth.jwt() ->> 'organization_id')::uuid
    AND (auth.jwt() -> 'app_metadata' ->> 'role')
        IN ('TENANT_ADMIN', 'OPERATOR', 'AUDITOR')
  );

-- ── Policy 2: WRITE for TENANT_ADMIN only ───────────────────────────────────
-- OPERATOR and AUDITOR are read-only for contractor management.
-- FOR ALL here covers INSERT/UPDATE/DELETE with USING + WITH CHECK.
-- For SELECT the "contractors_select_internal" policy handles access.
CREATE POLICY "contractors_write_admin"
  ON public.contractors
  FOR ALL
  TO authenticated
  USING (
    organization_id = (auth.jwt() ->> 'organization_id')::uuid
    AND (auth.jwt() -> 'app_metadata' ->> 'role') = 'TENANT_ADMIN'
  )
  WITH CHECK (
    organization_id = (auth.jwt() ->> 'organization_id')::uuid
    AND (auth.jwt() -> 'app_metadata' ->> 'role') = 'TENANT_ADMIN'
  );

-- ── Policy 3: CONTRACTOR_VIEWER dual-key isolation (INV-20) ─────────────────
-- Keep as-is. Reproduced here for clarity; no-op if already present.
DROP POLICY IF EXISTS "contractors_contractor_viewer_isolation" ON public.contractors;

CREATE POLICY "contractors_contractor_viewer_isolation"
  ON public.contractors
  FOR SELECT
  TO authenticated
  USING (
    organization_id = (auth.jwt() ->> 'organization_id')::uuid
    AND id = (auth.jwt() -> 'app_metadata' ->> 'contractor_id')::uuid
  );

COMMIT;
