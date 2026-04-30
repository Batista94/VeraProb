-- =============================================================================
-- Phase 3: Automated Enforcement & Governance Resilience (FIX-11, FIX-12, FIX-13)
-- =============================================================================
-- Hardens MFA lockout, unarchive integrity, and cross-domain quota triggers.
-- =============================================================================

-- 1. MFA Lockout Hardening (FIX-11): 3 attempts instead of 5
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
          WHEN super_admin_mfa_lockouts.locked_until IS NOT NULL
               AND super_admin_mfa_lockouts.locked_until <= NOW()
          THEN 1
          ELSE super_admin_mfa_lockouts.failed_attempts + 1
        END,
        locked_until = CASE
          WHEN super_admin_mfa_lockouts.locked_until IS NOT NULL
               AND super_admin_mfa_lockouts.locked_until <= NOW()
          THEN NULL
          WHEN (CASE
                  WHEN super_admin_mfa_lockouts.locked_until IS NOT NULL
                       AND super_admin_mfa_lockouts.locked_until <= NOW()
                  THEN 1
                  ELSE super_admin_mfa_lockouts.failed_attempts + 1
                END) >= 3 -- FIXED: 3 attempts (Enterprise Hardening)
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

-- 2. Unarchive Integrity (FIX-13): Don't allow unarchive if quotas are zero or invalid
CREATE OR REPLACE FUNCTION public.super_admin_unarchive_organization(
  p_org_id         UUID,
  p_reason         TEXT,
  p_super_admin_id UUID
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_max_v INT;
  v_max_c INT;
BEGIN
  -- JWT guard (INV-6)
  IF auth.uid() IS NOT NULL THEN
    IF (auth.jwt() -> 'app_metadata' ->> 'super_admin') IS DISTINCT FROM 'true' THEN
      RAISE EXCEPTION 'Unauthorized: super_admin claim required'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  -- Verify current state and fetch quotas
  SELECT max_vehicles, max_active_contracts INTO v_max_v, v_max_c
  FROM organizations WHERE id = p_org_id AND status = 'ARCHIVED';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Organization not archived or not found' USING ERRCODE = 'P0003';
  END IF;

  -- Phase 3: Integrity check (Integridade cross-domain)
  IF (v_max_v IS NOT NULL AND v_max_v <= 0) OR (v_max_c IS NOT NULL AND v_max_c <= 0) THEN
    RAISE EXCEPTION 'Cannot unarchive organization with zero quotas. Update quotas first.' 
      USING ERRCODE = 'P0004';
  END IF;

  UPDATE organizations SET status = 'ACTIVE', updated_at = NOW() WHERE id = p_org_id;

  -- Restore access
  UPDATE user_roles SET is_active = true WHERE organization_id = p_org_id;
  UPDATE auth.users SET banned_until = NULL 
   WHERE id IN (SELECT user_id FROM user_roles WHERE organization_id = p_org_id);

  INSERT INTO system_audit_log (event_type, severity, organization_id, reason, actor_type, source, payload)
  VALUES ('ORG_UNARCHIVED', 'info', p_org_id, p_reason, 'HUMAN', 'rpc', 
          jsonb_build_object('super_admin_id', p_super_admin_id, 'reason', p_reason));
END;
$$;

-- 3. Hard Quotas + Archive Guard (FIX-12)
-- We refine the triggers to also block inserts if the organization is ARCHIVED.
CREATE OR REPLACE FUNCTION public.enforce_vehicle_quota()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_max_vehicles INTEGER;
  v_current_count INTEGER;
  v_status TEXT;
BEGIN
  SELECT max_vehicles, status INTO v_max_vehicles, v_status
  FROM public.organizations WHERE id = NEW.organization_id;

  IF v_status = 'ARCHIVED' THEN
    RAISE EXCEPTION 'Cannot add vehicles to an ARCHIVED organization.' USING ERRCODE = 'P0005';
  END IF;

  IF v_max_vehicles IS NULL THEN RETURN NEW; END IF;

  SELECT COUNT(*) INTO v_current_count FROM public.vehicles
  WHERE organization_id = NEW.organization_id;

  IF v_current_count >= v_max_vehicles THEN
    RAISE EXCEPTION 'Vehicle quota reached (%)', v_max_vehicles USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.enforce_contract_quota()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_max_contracts INTEGER;
  v_current_count INTEGER;
  v_status TEXT;
BEGIN
  SELECT max_active_contracts, status INTO v_max_contracts, v_status
  FROM public.organizations WHERE id = NEW.organization_id;

  IF v_status = 'ARCHIVED' THEN
    RAISE EXCEPTION 'Cannot add contracts to an ARCHIVED organization.' USING ERRCODE = 'P0005';
  END IF;

  IF v_max_contracts IS NULL THEN RETURN NEW; END IF;

  SELECT COUNT(*) INTO v_current_count FROM public.contracts
  WHERE organization_id = NEW.organization_id AND status = 'active';

  IF v_current_count >= v_max_contracts THEN
    RAISE EXCEPTION 'Contract quota reached (%)', v_max_contracts USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;
