-- Migration: Explicit Data API Grants for Category B (Public / Token Tables)
-- Rule: INV-DATA-API-GRANT (Tables in public schema must explicitly grant API role access)
-- Target: anon (SELECT, INSERT, UPDATE), authenticated (SELECT, INSERT, UPDATE), service_role (ALL)

-- 1. Pre-create telegram_pending_links to allow early grants and avoid dependency issues on May 27, 2026
CREATE TABLE IF NOT EXISTS public.telegram_pending_links (
  id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  short_id            TEXT        NOT NULL,
  organization_id     UUID        NOT NULL,
  evidence_upload_id  UUID        NOT NULL REFERENCES public.telegram_evidence_uploads(id),
  execution_set_id    TEXT        NOT NULL,
  driver_id           UUID        NOT NULL,
  created_at_utc      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at_utc      TIMESTAMPTZ NOT NULL,
  is_resolved         BOOLEAN     NOT NULL DEFAULT FALSE,

  CONSTRAINT uq_tpl_short_id UNIQUE (short_id),
  CONSTRAINT chk_tpl_short_id_len CHECK (char_length(short_id) = 8)
);
ALTER TABLE public.telegram_pending_links ENABLE ROW LEVEL SECURITY;

-- 2. contract_review_tokens
REVOKE ALL ON TABLE public.contract_review_tokens FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON TABLE public.contract_review_tokens TO anon, authenticated;
GRANT ALL ON TABLE public.contract_review_tokens TO service_role;

-- 3. telegram_binding_tokens
REVOKE ALL ON TABLE public.telegram_binding_tokens FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON TABLE public.telegram_binding_tokens TO anon, authenticated;
GRANT ALL ON TABLE public.telegram_binding_tokens TO service_role;

-- 4. telegram_pending_links
REVOKE ALL ON TABLE public.telegram_pending_links FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON TABLE public.telegram_pending_links TO anon, authenticated;
GRANT ALL ON TABLE public.telegram_pending_links TO service_role;

-- 5. justification_submission_tokens
REVOKE ALL ON TABLE public.justification_submission_tokens FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON TABLE public.justification_submission_tokens TO anon, authenticated;
GRANT ALL ON TABLE public.justification_submission_tokens TO service_role;
