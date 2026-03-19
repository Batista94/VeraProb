-- Append-only audit table for spoofing detection results
-- Phase 8.8 — Anti-Spoofing Telemetry Integrity Audit
-- Created: 2026-03-19

CREATE TABLE IF NOT EXISTS public.spoofing_audit_entries (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id  UUID NOT NULL,
  device_id        TEXT NOT NULL,
  asset_id         UUID,
  window_start     TIMESTAMPTZ NOT NULL,
  window_end       TIMESTAMPTZ NOT NULL,
  risk_score       NUMERIC(4,3) NOT NULL CHECK (risk_score BETWEEN 0 AND 1),
  signals          JSONB NOT NULL DEFAULT '[]',
  facts_analyzed   INTEGER NOT NULL,
  fact_ids         UUID[] NOT NULL,
  content_hash     TEXT NOT NULL,   -- SHA-256 of the payload (INV-21)
  reviewed_by      UUID REFERENCES auth.users(id),
  reviewed_at      TIMESTAMPTZ,
  review_outcome   TEXT CHECK (review_outcome IN ('cleared', 'confirmed')),
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Immutability: no UPDATE/DELETE (INV-21 + qa_security req.)
-- Only allow updates to review columns, and only if they are NULL
CREATE POLICY spoofing_audit_no_delete ON public.spoofing_audit_entries
  FOR DELETE USING (false);

-- RLS: tenant isolation
ALTER TABLE public.spoofing_audit_entries ENABLE ROW LEVEL SECURITY;

CREATE POLICY spoofing_audit_tenant_read ON public.spoofing_audit_entries
  FOR SELECT USING (
    organization_id = (auth.jwt() ->> 'organization_id')::uuid
  );

CREATE POLICY spoofing_audit_tenant_insert ON public.spoofing_audit_entries
  FOR INSERT WITH CHECK (
    organization_id = (auth.jwt() ->> 'organization_id')::uuid
  );

-- Auditing Review Policy: Only auditors can review
-- For now, we allow any tenant user to insert (from Edge Function context)
-- and read (for OCC visibility). 
-- Review logic will be refined in RBAC Phase 6, but for now we block updates.
CREATE POLICY spoofing_audit_no_update ON public.spoofing_audit_entries
  FOR UPDATE USING (false);

-- Performance: queries por tenant + device + janela
CREATE INDEX IF NOT EXISTS idx_spoofing_audit_org_device
  ON public.spoofing_audit_entries(organization_id, device_id, window_start DESC);

CREATE INDEX IF NOT EXISTS idx_spoofing_audit_review_pending
  ON public.spoofing_audit_entries(organization_id, reviewed_at)
  WHERE reviewed_at IS NULL;

-- Comment for metadata
COMMENT ON TABLE public.spoofing_audit_entries IS 'Algorithmic GPS spoofing detections for forensic audit.';
