-- ============================================================
-- PactaFlow — Phase 6: User Invitations
-- ============================================================
-- REASON:
--   Allow organizations to invite new members without pre-existing
--   accounts in Supabase.
-- ============================================================

CREATE TABLE public.invitations (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID        NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  email           TEXT        NOT NULL,
  role            TEXT        NOT NULL,
  token           TEXT        NOT NULL UNIQUE,
  invited_by      UUID        NOT NULL, -- User who sent the invite
  created_at_utc  TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at_utc  TIMESTAMPTZ NOT NULL DEFAULT (now() + interval '7 days'),
  accepted_at_utc TIMESTAMPTZ,
  revoked_at_utc  TIMESTAMPTZ,

  -- Ensure email is unique per organization for pending invites
  CONSTRAINT uq_invitation_email_per_org UNIQUE (organization_id, email)
);

-- Index for token lookup
CREATE INDEX idx_invitations_token ON public.invitations (token);

-- RLS: Only admins can manage invitations
ALTER TABLE public.invitations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can manage invitations"
  ON public.invitations
  FOR ALL TO authenticated
  USING (
    organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid
    AND (auth.jwt() -> 'app_metadata' ->> 'role') = 'TENANT_ADMIN'
  )
  WITH CHECK (
    organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid
    AND (auth.jwt() -> 'app_metadata' ->> 'role') = 'TENANT_ADMIN'
  );

-- Public policy for token validation (during acceptance)
CREATE POLICY "Public token validation"
  ON public.invitations
  FOR SELECT TO anon, authenticated
  USING (revoked_at_utc IS NULL AND accepted_at_utc IS NULL AND expires_at_utc > now());
