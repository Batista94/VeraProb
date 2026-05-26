-- pr_scanner: ignore-regression
-- Phase 10.4.B — Bloco 2: PDF Dossier Logs
-- INV-1:  organization_id tenant isolation
-- INV-2:  RLS via JWT app_metadata.org_id
-- INV-6:  TIMESTAMPTZ mandatory
-- INV-9:  Store cryptographic hash of the document
-- INV-DB: Non-destructive CREATE

CREATE TABLE IF NOT EXISTS public.pdf_dossier_logs (
  id                   UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id      UUID        NOT NULL,
  sla_ledger_entry_id  UUID        NOT NULL,
  document_hash_sha256 TEXT        NOT NULL,
  generated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  generated_by         UUID        NOT NULL
);

COMMENT ON TABLE public.pdf_dossier_logs IS
  'Forensic audit log of PDF dossier generations (INV-9: Evidence Sealing).';

COMMENT ON COLUMN public.pdf_dossier_logs.document_hash_sha256 IS
  'SHA-256 hash of the final PDF contents or its data payload for immutability check.';

-- ── Indexes ──────────────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_pdf_dossier_logs_org
  ON public.pdf_dossier_logs (organization_id);

CREATE INDEX IF NOT EXISTS idx_pdf_dossier_logs_ledger
  ON public.pdf_dossier_logs (sla_ledger_entry_id);

-- ── RLS (INV-2) ──────────────────────────────────────────────────────────

ALTER TABLE public.pdf_dossier_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "PDF dossier logs tenant isolation"
  ON public.pdf_dossier_logs FOR ALL TO authenticated
  USING     (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::UUID)
  WITH CHECK (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::UUID);
