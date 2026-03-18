-- =============================================================================
-- Phase 8.1.4 — Technical Debt: Fix JWT Path in audit_packages RLS (INV-10)
-- =============================================================================
-- PROBLEM:
--   The original policy uses: (auth.jwt() ->> 'organization_id')::uuid
--   The custom_access_token_hook injects under: app_metadata.org_id
--   Result: policy silently returns 0 rows for all authenticated users.
--
-- FIX:
--   Align with the canonical INV-10 path used by all other tables since
--   migration 20260317000001_rls_jwt_path_unification.sql.
--
-- EXECUTE BEFORE: 20260402000002_contractor_viewer_dual_key.sql
-- =============================================================================

-- Drop the broken policy
DROP POLICY IF EXISTS "audit_packages_org_isolation" ON public.audit_packages;

-- Recreate with canonical JWT path (INV-10) + WITH CHECK for INSERT coverage
CREATE POLICY "audit_packages_tenant_isolation"
  ON public.audit_packages
  FOR ALL
  USING (
    organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid
  )
  WITH CHECK (
    organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid
  );

-- =============================================================================
-- VERIFICATION:
--   As an authenticated admin user:
--     SELECT count(*) FROM audit_packages;
--   Should return a number > 0 (previously returned 0 silently).
-- =============================================================================
