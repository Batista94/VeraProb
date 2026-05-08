--
-- =============================================================================
-- Phase 9.8.D — SuperAdmin Update Organization Quota RPC
-- =============================================================================
-- Allows a SuperAdmin to update an existing organization's plan type and quota
-- limits. Atomically updates the organizations row and appends an immutable
-- 'PLAN_CHANGED' billing event.
--
-- INV-1: Filtered by p_org_id (organization scope).
-- INV-7: Billing event is append-only (never UPDATE/DELETE).
-- INV-9: occurred_at_utc uses NOW() (database UTC clock).
-- INV-19: Limits are integers (counts), not Money.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.super_admin_update_organization_quota(
  p_org_id               UUID,
  p_new_plan_type        TEXT,
  p_new_max_vehicles     INT,       -- NULL = unlimited (enterprise tier)
  p_new_max_contracts    INT,       -- NULL = unlimited (enterprise tier)
  p_super_admin_user_id  UUID,
  p_reason               TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_old_plan          TEXT;
  v_old_max_vehicles  INT;
  v_old_max_contracts INT;
BEGIN
  -- ── JWT validation ──────────────────────────────────────────────────────────
  -- (auth.jwt() ->> 'sub') IS NULL indicates a service_role call (trusted, bypass allowed).
  -- When a real SuperAdmin session is present, validate the super_admin claim.
  IF (auth.jwt() ->> 'sub') IS NOT NULL THEN
    IF (auth.jwt() -> 'app_metadata' ->> 'super_admin') IS DISTINCT FROM 'true' THEN
      RAISE EXCEPTION 'Unauthorized: super_admin claim required'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  -- ── Input validation ────────────────────────────────────────────────────────
  IF p_new_plan_type NOT IN ('starter', 'professional', 'enterprise') THEN
    RAISE EXCEPTION 'Invalid plan_type: %. Must be starter, professional, or enterprise.',
      p_new_plan_type;
  END IF;

  -- Limits must be >= 1 when provided. NULL = unlimited (enterprise).
  IF p_new_max_vehicles IS NOT NULL AND p_new_max_vehicles < 1 THEN
    RAISE EXCEPTION 'max_vehicles must be >= 1 (or NULL for unlimited).';
  END IF;

  IF p_new_max_contracts IS NOT NULL AND p_new_max_contracts < 1 THEN
    RAISE EXCEPTION 'max_active_contracts must be >= 1 (or NULL for unlimited).';
  END IF;

  -- ── Read current values for billing event ───────────────────────────────────
  SELECT plan_type, max_vehicles, max_active_contracts
    INTO v_old_plan, v_old_max_vehicles, v_old_max_contracts
    FROM public.organizations
   WHERE id = p_org_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Organization % not found.', p_org_id;
  END IF;

  -- ── Update organization ─────────────────────────────────────────────────────
  UPDATE public.organizations
     SET plan_type            = p_new_plan_type,
         max_vehicles         = p_new_max_vehicles,
         max_active_contracts = p_new_max_contracts
   WHERE id = p_org_id;

  -- ── Append immutable billing event (INV-7) ──────────────────────────────────
  INSERT INTO public.tenant_billing_events (
    organization_id,
    event_type,
    old_plan,
    new_plan,
    old_max_vehicles,
    new_max_vehicles,
    old_max_contracts,
    new_max_contracts,
    changed_by_super_admin_id,
    reason,
    occurred_at_utc
  )
  VALUES (
    p_org_id,
    'PLAN_CHANGED',
    v_old_plan,
    p_new_plan_type,
    v_old_max_vehicles,
    p_new_max_vehicles,
    v_old_max_contracts,
    p_new_max_contracts,
    p_super_admin_user_id,
    p_reason,
    NOW()
  );
END;
$$;

REVOKE ALL ON FUNCTION public.super_admin_update_organization_quota(
  UUID, TEXT, INT, INT, UUID, TEXT
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.super_admin_update_organization_quota(
  UUID, TEXT, INT, INT, UUID, TEXT
) TO authenticated;
