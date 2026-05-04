-- pr_scanner: ignore-regression
-- =============================================================================
-- Stage A.3 — Per-Org API Secrets (INV-28: Org Secret Isolation)
-- =============================================================================
-- Each organization has a unique HMAC secret for signing telemetry.
-- Only the SHA-256 hash of the secret is stored — plain-text is returned
-- ONCE at generation time and never persisted.
--
-- Rotation is append-only: new version inserted, previous version gets
-- revoked_at timestamp. No UPDATE or DELETE allowed.
--
-- INV-9:  Evidence Sealing — HMAC per tenant.
-- INV-22: Tenant isolation — cross-tenant HMAC mismatch = quarantine.
-- INV-28: NEW — Org Secret Isolation.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.org_api_secrets (
  id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id  UUID        NOT NULL REFERENCES public.organizations(id),
  secret_hash      TEXT        NOT NULL,
  version          INT         NOT NULL DEFAULT 1,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  rotated_at       TIMESTAMPTZ,
  revoked_at       TIMESTAMPTZ,

  -- Only one active (non-revoked) secret per org at a time
  CONSTRAINT uq_org_api_secrets_active
    EXCLUDE USING btree (organization_id WITH =)
    WHERE (revoked_at IS NULL)
);

-- ── Immutability: append-only rotation ───────────────────────────────────────
-- Block UPDATE on all columns except revoked_at (needed for rotation).
-- Block DELETE entirely.
CREATE OR REPLACE FUNCTION public.org_api_secrets_immutability_guard()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'org_api_secrets is append-only: DELETE is forbidden'
      USING ERRCODE = 'restrict_violation';
  END IF;

  IF TG_OP = 'UPDATE' THEN
    -- Only allow setting revoked_at on a previously non-revoked row
    IF OLD.revoked_at IS NOT NULL THEN
      RAISE EXCEPTION 'Cannot modify an already-revoked secret'
        USING ERRCODE = 'restrict_violation';
    END IF;
    IF NEW.secret_hash IS DISTINCT FROM OLD.secret_hash
       OR NEW.version IS DISTINCT FROM OLD.version
       OR NEW.organization_id IS DISTINCT FROM OLD.organization_id
       OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
      RAISE EXCEPTION 'org_api_secrets is append-only: only revoked_at and rotated_at may be updated'
        USING ERRCODE = 'restrict_violation';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_org_api_secrets_immutability
  BEFORE UPDATE OR DELETE ON public.org_api_secrets
  FOR EACH ROW EXECUTE FUNCTION public.org_api_secrets_immutability_guard();

-- ── Indexes ──────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_org_api_secrets_org_active
  ON public.org_api_secrets (organization_id)
  WHERE revoked_at IS NULL;

-- ── RLS: service_role only (no direct client access) ─────────────────────────
ALTER TABLE public.org_api_secrets ENABLE ROW LEVEL SECURITY;

-- No policies for authenticated role = deny-all for regular users.
-- service_role bypasses RLS automatically.
-- Edge Functions use service_role key to read/write secrets.

COMMENT ON TABLE public.org_api_secrets IS
  'INV-28: Per-org HMAC secrets. Append-only rotation. Only secret_hash stored (never plain-text). '
  'service_role access only — no authenticated user policies.';
