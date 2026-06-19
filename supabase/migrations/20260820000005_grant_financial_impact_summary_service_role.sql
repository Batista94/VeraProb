-- Migration: Redefine get_financial_impact_summary and Grant EXECUTE to service_role
-- Reason: Restores service_role execution permission and adds service_role/postgres bypass 
--         for tenant isolation check (INV-2) to unblock E2E and background tasks.

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
  v_caller_org_id UUID;
  v_protected     BIGINT := 0;
  v_at_risk       BIGINT := 0;
  v_lost          BIGINT := 0;
BEGIN
  -- INV-2: Strict validation against JWT app_metadata (bypass for system/admin roles)
  IF current_user IN ('service_role', 'postgres') THEN
    v_caller_org_id := p_org_id;
  ELSE
    v_caller_org_id := (current_setting('request.jwt.claims', true)::jsonb -> 'app_metadata' ->> 'org_id')::UUID;
  END IF;
  
  IF v_caller_org_id IS NULL OR p_org_id IS NULL OR v_caller_org_id != p_org_id THEN
    RAISE EXCEPTION 'Access denied. Tenant isolation violation (INV-2).' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Aggregate sums. 
  -- Savings: applied, acknowledged
  -- At Risk: pending, disputed, pending_peer_review
  -- Lost: rejected
  SELECT
    COALESCE(SUM(CASE WHEN status IN ('applied', 'acknowledged') THEN (verdict_evidence ->> 'fine_cents')::BIGINT ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN status IN ('pending', 'disputed', 'pending_peer_review') THEN (verdict_evidence ->> 'fine_cents')::BIGINT ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN status = 'rejected' THEN (verdict_evidence ->> 'fine_cents')::BIGINT ELSE 0 END), 0)
  INTO v_protected, v_at_risk, v_lost
  FROM public.sanction_review_queue
  WHERE organization_id = p_org_id;

  RETURN jsonb_build_object(
    'protected_revenue_cents', v_protected,
    'revenue_at_risk_cents', v_at_risk,
    'lost_revenue_cents', v_lost
  );
END;
$$;

-- Ensure execution permissions are granted to authenticated and service_role
REVOKE ALL ON FUNCTION public.get_financial_impact_summary(UUID) FROM PUBLIC, service_role;
GRANT EXECUTE ON FUNCTION public.get_financial_impact_summary(UUID) TO authenticated, service_role;

RESET client_min_messages;
