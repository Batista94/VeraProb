-- =============================================================================
-- Migration: Webhook Signing Keys
-- INV-22: Tenant Isolation
-- INV-28: Org Secret Isolation (Metadata Only)
-- INV-31: No cryptographic material at rest.
-- =============================================================================

CREATE TYPE webhook_signing_key_status AS ENUM ('active', 'retiring', 'revoked');

CREATE TABLE IF NOT EXISTS public.webhook_signing_keys (
  id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id  UUID        NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  version          INT         NOT NULL DEFAULT 1,
  status           webhook_signing_key_status NOT NULL DEFAULT 'active',
  retiring_until   TIMESTAMPTZ,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- Only one active key per org at a time
  CONSTRAINT uq_webhook_signing_keys_active
    EXCLUDE USING btree (organization_id WITH =)
    WHERE (status = 'active')
);

-- RLS
ALTER TABLE public.webhook_signing_keys ENABLE ROW LEVEL SECURITY;

-- Grants (Data API constraint)
GRANT SELECT, INSERT, UPDATE ON public.webhook_signing_keys TO authenticated;

CREATE POLICY "Tenant Admins can manage webhook signing keys"
  ON public.webhook_signing_keys
  AS PERMISSIVE
  FOR ALL
  TO authenticated
  USING (
    organization_id::text = (auth.jwt() ->> 'organization_id')
    AND (auth.jwt() ->> 'user_role') = 'admin'
  )
  WITH CHECK (
    organization_id::text = (auth.jwt() ->> 'organization_id')
    AND (auth.jwt() ->> 'user_role') = 'admin'
  );

COMMENT ON TABLE public.webhook_signing_keys IS 'INV-31: Stores only metadata for webhook signing keys. No key material stored.';
