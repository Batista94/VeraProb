-- Migration: Fix contracts RLS policy — wrong JWT claim path
-- The original policy referenced auth.jwt() ->> 'organization_id' (top-level, wrong key).
-- The custom_access_token_hook injects org_id under app_metadata, not as a top-level claim.
-- Correct path: auth.jwt() -> 'app_metadata' ->> 'org_id'

DROP POLICY IF EXISTS "Contract tenant isolation" ON public.contracts;

CREATE POLICY "Contract tenant isolation"
  ON public.contracts FOR ALL TO authenticated
  USING     (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::UUID)
  WITH CHECK (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::UUID);
