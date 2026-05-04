-- pr_scanner: ignore-regression
-- ─────────────────────────────────────────────────────────────────────────────
-- INV-31: HMAC Zero-Knowledge — add payload_hmac to ingest/ledger tables.
-- Signed exclusively in Edge Functions (Deno); DB is "blind" to the key.
-- Existing rows receive NULL (pre-INV-31 data; verified as legacy on read).
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.telegram_evidence_uploads
  ADD COLUMN IF NOT EXISTS payload_hmac TEXT;

COMMENT ON COLUMN public.telegram_evidence_uploads.payload_hmac IS
  'INV-31: versioned HMAC-SHA256 over canonical evidence payload. Format: v{N}|{hex64}. NULL for pre-INV-31 rows.';

ALTER TABLE public.sla_audit_ledger
  ADD COLUMN IF NOT EXISTS payload_hmac TEXT;

COMMENT ON COLUMN public.sla_audit_ledger.payload_hmac IS
  'INV-31: versioned HMAC-SHA256 over canonical ledger payload. Format: v{N}|{hex64}. NULL for pre-INV-31 rows.';
