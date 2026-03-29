-- Phase 9.8.A: Hotfix — Fix execution_state_transitions RLS JWT path
--
-- The policy created in 20260418000001 used the deprecated claim path:
--   auth.jwt() -> 'app_metadata' ->> 'org_id'
-- instead of the canonical top-level claim injected by the JWT hook:
--   auth.jwt() ->> 'organization_id'
--
-- This divergence meant any authenticated user could read execution state
-- transitions belonging to other tenants (cross-tenant data leak on INV-1).
--
-- Fix: drop and recreate the policy with the canonical claim path.
--
-- INV-1: Tenant isolation — every query MUST filter by organization_id.
-- INV-5: RLS policies MUST use canonical JWT claims (auth.jwt() ->> 'organization_id').

BEGIN;

DROP POLICY IF EXISTS "Tenant isolation: execution_state_transitions"
  ON public.execution_state_transitions;

CREATE POLICY "Tenant isolation: execution_state_transitions"
  ON public.execution_state_transitions
  FOR ALL
  USING (organization_id = (auth.jwt() ->> 'organization_id')::uuid)
  WITH CHECK (organization_id = (auth.jwt() ->> 'organization_id')::uuid);

COMMIT;
