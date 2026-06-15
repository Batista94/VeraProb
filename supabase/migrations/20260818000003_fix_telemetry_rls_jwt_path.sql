-- =============================================================================
-- Migration: Fix raw_telemetry_payloads & canonical_facts JWT Path (INV-2)
-- 
-- The initial migration (20260325000001) incorrectly used `auth.jwt() ->> 'organization_id'`.
-- Per INV-2, the correct path is `auth.jwt() -> 'app_metadata' ->> 'org_id'`.
-- This caused 42501 permission denied errors when the DevSeeder attempted
-- to insert simulated telemetry payloads.
-- =============================================================================

-- 1. Fix raw_telemetry_payloads
DROP POLICY IF EXISTS "raw_telemetry_payloads_org_isolation" ON public.raw_telemetry_payloads;

CREATE POLICY "raw_telemetry_payloads_org_isolation"
  ON public.raw_telemetry_payloads
  FOR ALL
  USING (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid)
  WITH CHECK (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid);

-- 2. Fix canonical_facts
DROP POLICY IF EXISTS "canonical_facts_org_isolation" ON public.canonical_facts;

CREATE POLICY "canonical_facts_org_isolation"
  ON public.canonical_facts
  FOR ALL
  USING (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid)
  WITH CHECK (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid);
