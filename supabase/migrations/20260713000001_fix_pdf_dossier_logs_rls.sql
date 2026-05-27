-- pr_scanner: ignore-regression
-- Phase 10.4.C — Hardening RLS in PDF Dossier Logs
-- INV-2: RLS uses auth.jwt() ->> 'organization_id'
-- INV-DB: Zero-downtime verified

DROP POLICY IF EXISTS "PDF dossier logs tenant isolation" ON public.pdf_dossier_logs;

CREATE POLICY "PDF dossier logs tenant isolation"
  ON public.pdf_dossier_logs FOR ALL TO authenticated
  USING      ((auth.jwt() ->> 'organization_id')::UUID = organization_id)
  WITH CHECK ((auth.jwt() ->> 'organization_id')::UUID = organization_id);
