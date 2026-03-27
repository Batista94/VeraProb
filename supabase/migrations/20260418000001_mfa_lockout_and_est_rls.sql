-- Phase 9.6.A.2: MFA Circuit Breaker + execution_state_transitions RLS fix
--
-- Creates:
--   A. super_admin_mfa_lockouts — tracks failed MFA attempts per SuperAdmin user
--   B. super_admin_recovery_codes — SHA-256 hashed backup codes
--   C. RPCs: record_mfa_failure, reset_mfa_lockout, check_mfa_lockout
--   D. execution_state_transitions — adds organization_id + RLS (security audit fix)
--
-- INV-6: SuperAdmin access requires MFA + super_admin=true JWT claim.
-- INV-1: Tenant isolation on execution_state_transitions (previously missing).

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════════
-- A. MFA Lockout Table
-- ═══════════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.super_admin_mfa_lockouts (
  user_id    UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  failed_attempts  INT NOT NULL DEFAULT 0,
  locked_until     TIMESTAMPTZ,
  last_attempt     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.super_admin_mfa_lockouts ENABLE ROW LEVEL SECURITY;

-- No authenticated access — only SECURITY DEFINER RPCs and service_role.
-- (No SELECT/INSERT/UPDATE/DELETE policies for authenticated role.)

COMMENT ON TABLE public.super_admin_mfa_lockouts IS
  'Circuit breaker for SuperAdmin MFA — tracks failed TOTP attempts. INV-6.';

-- ═══════════════════════════════════════════════════════════════════════════════
-- B. Recovery Codes Table
-- ═══════════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.super_admin_recovery_codes (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  code_hash  TEXT NOT NULL,
  used_at    TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_recovery_codes_user_id ON public.super_admin_recovery_codes(user_id);

ALTER TABLE public.super_admin_recovery_codes ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public.super_admin_recovery_codes IS
  'SHA-256 hashed MFA recovery codes for SuperAdmin users. INV-6.';

-- ═══════════════════════════════════════════════════════════════════════════════
-- C. RPCs — SECURITY DEFINER (callable by authenticated JWT, executes as owner)
-- ═══════════════════════════════════════════════════════════════════════════════

-- C.1 Record a failed MFA attempt. At 5 failures → 15-minute lockout.
CREATE OR REPLACE FUNCTION public.record_mfa_failure(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_attempts INT;
  v_locked_until TIMESTAMPTZ;
BEGIN
  INSERT INTO super_admin_mfa_lockouts (user_id, failed_attempts, last_attempt)
  VALUES (p_user_id, 1, NOW())
  ON CONFLICT (user_id) DO UPDATE
    SET failed_attempts = CASE
          -- If previous lockout expired, reset counter to 1
          WHEN super_admin_mfa_lockouts.locked_until IS NOT NULL
               AND super_admin_mfa_lockouts.locked_until <= NOW()
          THEN 1
          ELSE super_admin_mfa_lockouts.failed_attempts + 1
        END,
        locked_until = CASE
          WHEN super_admin_mfa_lockouts.locked_until IS NOT NULL
               AND super_admin_mfa_lockouts.locked_until <= NOW()
          THEN NULL  -- Reset expired lockout
          WHEN (CASE
                  WHEN super_admin_mfa_lockouts.locked_until IS NOT NULL
                       AND super_admin_mfa_lockouts.locked_until <= NOW()
                  THEN 1
                  ELSE super_admin_mfa_lockouts.failed_attempts + 1
                END) >= 5
          THEN NOW() + INTERVAL '15 minutes'
          ELSE super_admin_mfa_lockouts.locked_until
        END,
        last_attempt = NOW()
  RETURNING failed_attempts, locked_until
  INTO v_attempts, v_locked_until;

  RETURN jsonb_build_object(
    'failed_attempts', v_attempts,
    'locked_until', v_locked_until,
    'is_locked', (v_locked_until IS NOT NULL AND v_locked_until > NOW())
  );
END;
$$;

-- C.2 Reset lockout on successful MFA verification.
CREATE OR REPLACE FUNCTION public.reset_mfa_lockout(p_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  DELETE FROM super_admin_mfa_lockouts WHERE user_id = p_user_id;
END;
$$;

-- C.3 Check current lockout status. Auto-expires stale locks.
CREATE OR REPLACE FUNCTION public.check_mfa_lockout(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row super_admin_mfa_lockouts%ROWTYPE;
BEGIN
  SELECT * INTO v_row FROM super_admin_mfa_lockouts WHERE user_id = p_user_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'failed_attempts', 0,
      'locked_until', NULL,
      'is_locked', false
    );
  END IF;

  -- Auto-expire stale lockout
  IF v_row.locked_until IS NOT NULL AND v_row.locked_until <= NOW() THEN
    DELETE FROM super_admin_mfa_lockouts WHERE user_id = p_user_id;
    RETURN jsonb_build_object(
      'failed_attempts', 0,
      'locked_until', NULL,
      'is_locked', false
    );
  END IF;

  RETURN jsonb_build_object(
    'failed_attempts', v_row.failed_attempts,
    'locked_until', v_row.locked_until,
    'is_locked', (v_row.locked_until IS NOT NULL AND v_row.locked_until > NOW())
  );
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════════
-- D. Fix: execution_state_transitions — add organization_id + RLS
-- ═══════════════════════════════════════════════════════════════════════════════

-- D.1 Add column (nullable first for backfill)
ALTER TABLE public.execution_state_transitions
  ADD COLUMN IF NOT EXISTS organization_id UUID REFERENCES public.organizations(id);

-- D.2 Backfill from parent execution_states
UPDATE public.execution_state_transitions est
SET organization_id = es.organization_id
FROM public.execution_states es
WHERE est.execution_state_id = es.id
  AND est.organization_id IS NULL;

-- D.3 Make NOT NULL after backfill
ALTER TABLE public.execution_state_transitions
  ALTER COLUMN organization_id SET NOT NULL;

-- D.4 Index for RLS performance
CREATE INDEX IF NOT EXISTS idx_est_transitions_org_id
  ON public.execution_state_transitions(organization_id);

-- D.5 Enable RLS
ALTER TABLE public.execution_state_transitions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Tenant isolation: execution_state_transitions"
  ON public.execution_state_transitions
  FOR ALL
  USING (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid)
  WITH CHECK (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid);

COMMIT;
