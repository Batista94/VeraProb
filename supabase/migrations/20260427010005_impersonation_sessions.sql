-- pr_scanner: ignore-regression
-- =============================================================================
-- Stage A.5 — Impersonation Sessions
-- =============================================================================
-- Tracks SuperAdmin impersonation sessions for audit and security.
-- Each session issues a temporary JWT with target_org_id as organization_id.
--
-- Security model:
--   - Max 1 active session per impersonator (DB trigger enforced)
--   - Sessions expire after 30 minutes (enforced by Edge Function)
--   - Revocation sets revoked_at (JWT still valid until exp, but Edge Function checks)
--   - ticket_id is mandatory (links to support ticket for accountability)
--
-- INV-1:  target_org_id becomes the JWT organization_id during impersonation.
-- INV-2:  RLS evaluates target_org_id from the temporary JWT.
-- INV-22: Impersonator with target_org=A cannot access org B data.
-- INV-26: Impersonation of non-existent/deleted org → 404 (same as wrong org).
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.impersonation_sessions (
  id                     UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  impersonator_user_id   UUID        NOT NULL,
  target_org_id          UUID        NOT NULL REFERENCES public.organizations(id),
  target_user_id         UUID,
  issued_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at             TIMESTAMPTZ NOT NULL,
  revoked_at             TIMESTAMPTZ,
  revocation_reason      TEXT,
  ticket_id              TEXT        NOT NULL,

  -- Ensure expires_at is in the future at creation
  CONSTRAINT chk_impersonation_expires_future
    CHECK (expires_at > issued_at)
);

-- ── Trigger: max 1 active session per impersonator ───────────────────────────
CREATE OR REPLACE FUNCTION public.impersonation_sessions_max_one_active()
RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  v_active_count INT;
BEGIN
  SELECT COUNT(*) INTO v_active_count
  FROM public.impersonation_sessions
  WHERE impersonator_user_id = NEW.impersonator_user_id
    AND revoked_at IS NULL
    AND expires_at > NOW();

  IF v_active_count > 0 THEN
    RAISE EXCEPTION 'Impersonator % already has an active session. Revoke it first.',
      NEW.impersonator_user_id
      USING ERRCODE = 'unique_violation';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_impersonation_max_one_active ON public.impersonation_sessions;
CREATE TRIGGER trg_impersonation_max_one_active
  BEFORE INSERT ON public.impersonation_sessions
  FOR EACH ROW EXECUTE FUNCTION public.impersonation_sessions_max_one_active();

-- ── Indexes ──────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_impersonation_sessions_impersonator_active
  ON public.impersonation_sessions (impersonator_user_id)
  WHERE revoked_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_impersonation_sessions_target_org
  ON public.impersonation_sessions (target_org_id, issued_at DESC);

-- ── RLS: service_role only (no direct client access) ─────────────────────────
ALTER TABLE public.impersonation_sessions ENABLE ROW LEVEL SECURITY;

-- No policies for authenticated role = deny-all for regular users.
-- Edge Functions use service_role key to manage sessions.

-- ── Immutability: only revoked_at and revocation_reason may be updated ───────
CREATE OR REPLACE FUNCTION public.impersonation_sessions_immutability_guard()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'impersonation_sessions is append-only: DELETE is forbidden'
      USING ERRCODE = 'restrict_violation';
  END IF;

  IF TG_OP = 'UPDATE' THEN
    IF NEW.impersonator_user_id IS DISTINCT FROM OLD.impersonator_user_id
       OR NEW.target_org_id IS DISTINCT FROM OLD.target_org_id
       OR NEW.target_user_id IS DISTINCT FROM OLD.target_user_id
       OR NEW.issued_at IS DISTINCT FROM OLD.issued_at
       OR NEW.expires_at IS DISTINCT FROM OLD.expires_at
       OR NEW.ticket_id IS DISTINCT FROM OLD.ticket_id THEN
      RAISE EXCEPTION 'impersonation_sessions: only revoked_at and revocation_reason may be updated'
        USING ERRCODE = 'restrict_violation';
    END IF;
    -- Cannot un-revoke a session
    IF OLD.revoked_at IS NOT NULL AND NEW.revoked_at IS DISTINCT FROM OLD.revoked_at THEN
      RAISE EXCEPTION 'Cannot modify revoked_at on an already-revoked session'
        USING ERRCODE = 'restrict_violation';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_impersonation_sessions_immutability ON public.impersonation_sessions;
CREATE TRIGGER trg_impersonation_sessions_immutability
  BEFORE UPDATE OR DELETE ON public.impersonation_sessions
  FOR EACH ROW EXECUTE FUNCTION public.impersonation_sessions_immutability_guard();

COMMENT ON TABLE public.impersonation_sessions IS
  'Tracks SuperAdmin impersonation sessions. Max 1 active per impersonator. '
  'Append-only: only revoked_at/revocation_reason may be updated. service_role access only.';
