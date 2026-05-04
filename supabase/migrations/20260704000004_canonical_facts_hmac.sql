-- pr_scanner: ignore-regression
-- ─────────────────────────────────────────────────────────────────────────────
-- INV-31: HMAC Zero-Knowledge — add payload_hmac to canonical_facts.
-- Signed exclusively in ingest Edge Functions (Deno); DB is "blind" to the key.
-- Existing rows receive NULL (pre-INV-31 data; verified as legacy on read).
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.canonical_facts
  ADD COLUMN IF NOT EXISTS payload_hmac TEXT;

COMMENT ON COLUMN public.canonical_facts.payload_hmac IS
  'INV-31: versioned HMAC-SHA256 over canonical fact payload. Format: v{N}|{hex64}. NULL for pre-INV-31 rows.';
