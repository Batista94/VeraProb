-- =============================================================================
-- Migration: fix_financial_impact_security_bypass
-- Purpose:   Replaces the postgres/service_role DB-role bypass in
--            get_financial_impact_summary with a correct JWT-claims-based check.
--
-- Old approach: IF current_user IN ('service_role', 'postgres') THEN bypass
-- Problem:      pgTAP always runs as 'postgres' superuser, so ALL test cases
--               were bypassed — including the IDOR security assertions (TC4/TC8/TC9).
--
-- Correct approach:
--   1. No JWT context (v_raw_claims IS NULL or '')  → trusted backend call, bypass OK.
--   2. JWT role claim = 'service_role'              → Supabase Edge Function with
--                                                     service_role key, bypass OK.
--   3. JWT present with app_metadata.org_id         → enforce tenant isolation.
--   4. JWT present but no org_id (anon, bad token)  → raise 42501.
--
-- INV-2: RLS / tenant isolation enforcement.
-- INV-22: Tenant-A NEVER sees Tenant-B data.
-- =============================================================================

SET client_min_messages TO 'WARNING';

CREATE OR REPLACE FUNCTION public.get_financial_impact_summary(
  p_org_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_raw_claims    TEXT;
  v_claims_json   JSONB;
  v_jwt_role      TEXT;
  v_caller_org_id UUID;
  v_protected     BIGINT := 0;
  v_at_risk       BIGINT := 0;
  v_lost          BIGINT := 0;
BEGIN
  -- INV-2: Determine the caller's org from JWT claims when present.
  --
  -- Bypass conditions (trusted paths):
  --   (a) No JWT context at all (NULL / empty string): backend internal call
  --       with no JWT forwarding (e.g., service-side cron, pgTAP schema setup).
  --   (b) JWT role = 'service_role': Supabase Edge Function authenticating with
  --       the service_role key. Supabase sets this claim automatically.
  --
  -- All other callers must have app_metadata.org_id matching p_org_id.
  v_raw_claims := current_setting('request.jwt.claims', true);

  IF v_raw_claims IS NULL OR v_raw_claims = '' THEN
    -- Trusted backend path: no JWT context present. Accept p_org_id directly.
    v_caller_org_id := p_org_id;
  ELSE
    v_claims_json := v_raw_claims::jsonb;
    v_jwt_role    := v_claims_json ->> 'role';

    IF v_jwt_role = 'service_role' THEN
      -- Supabase service_role key path: bypass tenant check.
      v_caller_org_id := p_org_id;
    ELSE
      -- Standard authenticated/anon path: extract and validate app_metadata.org_id.
      v_caller_org_id := (v_claims_json -> 'app_metadata' ->> 'org_id')::UUID;
    END IF;
  END IF;

  IF v_caller_org_id IS NULL OR p_org_id IS NULL OR v_caller_org_id != p_org_id THEN
    RAISE EXCEPTION 'Access denied. Tenant isolation violation (INV-2).'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Aggregate sums.
  -- Savings:  applied, acknowledged
  -- At Risk:  pending, disputed, pending_peer_review
  -- Lost:     rejected
  SELECT
    COALESCE(SUM(CASE WHEN status IN ('applied', 'acknowledged') THEN (verdict_evidence ->> 'fine_cents')::BIGINT ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN status IN ('pending', 'disputed', 'pending_peer_review') THEN (verdict_evidence ->> 'fine_cents')::BIGINT ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN status = 'rejected' THEN (verdict_evidence ->> 'fine_cents')::BIGINT ELSE 0 END), 0)
  INTO v_protected, v_at_risk, v_lost
  FROM public.sanction_review_queue
  WHERE organization_id = p_org_id;

  RETURN jsonb_build_object(
    'protected_revenue_cents', v_protected,
    'revenue_at_risk_cents',   v_at_risk,
    'lost_revenue_cents',      v_lost
  );
END;
$$;

-- Preserve grants from 20260820000005.
REVOKE ALL ON FUNCTION public.get_financial_impact_summary(UUID) FROM PUBLIC, service_role;
GRANT EXECUTE ON FUNCTION public.get_financial_impact_summary(UUID) TO authenticated, service_role;

RESET client_min_messages;
