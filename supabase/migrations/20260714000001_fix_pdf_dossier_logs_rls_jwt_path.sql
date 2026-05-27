-- pr_scanner: ignore-regression — INV-2 corrective, Council-reviewed BLOCKER-1
-- Corrective migration: Fix JWT claim path for pdf_dossier_logs RLS
-- INV-2:  auth.jwt() -> 'app_metadata' ->> 'org_id' (NEVER top-level ->> 'organization_id')
-- INV-22: Tenant-A MUST NOT see Tenant-B data
-- INV-DB: Zero-downtime policy replacement (DROP IF EXISTS + CREATE)
--
-- Context: Migration 20260713000001 introduced an RLS policy using the WRONG
-- JWT claim path (auth.jwt() ->> 'organization_id'). The custom_access_token_hook
-- injects org_id under app_metadata, so the correct path is:
--   auth.jwt() -> 'app_metadata' ->> 'org_id'
-- The wrong path causes the policy to NEVER match, silently blocking all rows.

DROP POLICY IF EXISTS "PDF dossier logs tenant isolation" ON public.pdf_dossier_logs;

CREATE POLICY "PDF dossier logs tenant isolation"
  ON public.pdf_dossier_logs FOR ALL TO authenticated
  USING      (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::UUID)
  WITH CHECK (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::UUID);
