-- Migration: 20260408000003_fix_contractors_rls_jwt_path.sql
--
-- Fix: contractors and contracts table RLS policies were using deprecated JWT claim path:
--   auth.jwt() -> 'app_metadata' ->> 'org_id'
-- instead of the canonical top-level claim injected by the JWT hook:
--   auth.jwt() ->> 'organization_id'
--
-- This divergence caused PGRST116 in AUDIT 4 (LGPD Masking test) because
-- the OPERATOR role could not access ANY contractors rows — the org_id
-- comparison always failed (NULL != valid UUID), resulting in 0 rows.
--
-- Aligns contractors/contracts RLS with INV-5 canonical JWT claims standard.
-- Also updates CONTRACTOR_VIEWER policy for consistency.

BEGIN;

-- ============================================================================
-- CONTRACTORS TABLE
-- ============================================================================

-- Policy 1: Internal roles (TENANT_ADMIN, OPERATOR, AUDITOR)
DROP POLICY IF EXISTS "contractors_internal_roles" ON public.contractors;

CREATE POLICY "contractors_internal_roles"
  ON public.contractors
  FOR ALL
  USING (
    organization_id = (auth.jwt() ->> 'organization_id')::uuid
    AND (auth.jwt() -> 'app_metadata' ->> 'contractor_id') IS NULL
  )
  WITH CHECK (
    organization_id = (auth.jwt() ->> 'organization_id')::uuid
    AND (auth.jwt() -> 'app_metadata' ->> 'contractor_id') IS NULL
  );

-- Policy 2: CONTRACTOR_VIEWER — sees only their OWN contractor record
DROP POLICY IF EXISTS "contractors_contractor_viewer_isolation" ON public.contractors;

CREATE POLICY "contractors_contractor_viewer_isolation"
  ON public.contractors
  FOR SELECT
  USING (
    organization_id = (auth.jwt() ->> 'organization_id')::uuid
    AND id = (auth.jwt() -> 'app_metadata' ->> 'contractor_id')::uuid
  );

-- ============================================================================
-- CONTRACTS TABLE
-- ============================================================================

-- Policy 1: Internal roles — org isolation + contractor_id NULL guard
DROP POLICY IF EXISTS "contracts_internal_roles" ON public.contracts;

CREATE POLICY "contracts_internal_roles"
  ON public.contracts
  FOR ALL
  USING (
    organization_id = (auth.jwt() ->> 'organization_id')::uuid
    AND (auth.jwt() -> 'app_metadata' ->> 'contractor_id') IS NULL
  )
  WITH CHECK (
    organization_id = (auth.jwt() ->> 'organization_id')::uuid
    AND (auth.jwt() -> 'app_metadata' ->> 'contractor_id') IS NULL
  );

-- Policy 2: CONTRACTOR_VIEWER — read contracts where their contractor is involved
DROP POLICY IF EXISTS "contracts_contractor_viewer_isolation" ON public.contracts;

CREATE POLICY "contracts_contractor_viewer_isolation"
  ON public.contracts
  FOR SELECT
  USING (
    organization_id = (auth.jwt() ->> 'organization_id')::uuid
    AND EXISTS (
      SELECT 1
      FROM public.contractors c
      WHERE c.organization_id = contracts.organization_id
        AND c.id = (auth.jwt() -> 'app_metadata' ->> 'contractor_id')::uuid
        AND (
          c.name = contracts.contractor_name
        )
    )
  );

COMMIT;
