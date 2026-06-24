-- Migration: get_financial_impact_summary RPC
-- Replaces mock analytics with aggregated sanction_review_queue data.
-- Security Model: SECURITY DEFINER, checks INV-2 claim.

SET client_min_messages TO 'WARNING';

-- Ensure index exists on organization_id, status to avoid Full Table Scan
CREATE INDEX IF NOT EXISTS idx_srq_org_status
  ON public.sanction_review_queue (organization_id, status);

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
  -- INV-2: Strict validation against JWT app_metadata
  v_caller_org_id := (current_setting('request.jwt.claims', true)::jsonb -> 'app_metadata' ->> 'org_id')::UUID;
  
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

-- Grant to authenticated only (service_role omitted via PUBLIC revoke, mirrors standard)
REVOKE ALL ON FUNCTION public.get_financial_impact_summary(UUID) FROM PUBLIC, service_role;
GRANT EXECUTE ON FUNCTION public.get_financial_impact_summary(UUID) TO authenticated;
