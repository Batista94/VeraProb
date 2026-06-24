-- Migration: Redefine get_financial_impact_summary, prevent_srq_delete and test_cleanup_forensic_data
-- Reason: Restores service_role execution permission, adds service_role/postgres bypass 
--         for tenant isolation check (INV-2) in get_financial_impact_summary, and updates
--         test cleanup helpers to support sanction_review_queue cleanup.

SET client_min_messages TO 'WARNING';

-- 1. Redefine get_financial_impact_summary with service_role/postgres bypass
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

-- 2. Make prevent_srq_delete GUC-aware for test cleanup
CREATE OR REPLACE FUNCTION public.prevent_srq_delete()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF current_setting('vera.authorized_test_cleanup', true) = 'on' THEN
    RETURN OLD;
  END IF;
  RAISE EXCEPTION
    'sanction_review_queue is append-only (INV-1). DELETE blocked. id: %', OLD.id
  USING ERRCODE = 'restrict_violation';
END;
$$;

-- 3. Redefine test_cleanup_forensic_data to include sanction_review_queue
CREATE OR REPLACE FUNCTION public.test_cleanup_forensic_data(p_org_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Authorize this transaction for test cleanup (scoped to this TX only)
  SET LOCAL vera.authorized_test_cleanup = 'on';

  -- Delete in reverse FK order (Shadow Mode cleanup first)
  DELETE FROM public.shadow_execution_transitions  WHERE organization_id = p_org_id; -- pr_scanner: ignore
  DELETE FROM public.shadow_executions             WHERE organization_id = p_org_id; -- pr_scanner: ignore
  DELETE FROM public.shadow_verdicts               WHERE organization_id = p_org_id; -- pr_scanner: ignore

  -- Delete sanction review queue entries for this organization
  DELETE FROM public.sanction_review_queue         WHERE organization_id = p_org_id; -- pr_scanner: ignore

  -- Telegram evidence chain
  DELETE FROM public.telegram_evidence_links       WHERE organization_id = p_org_id; -- pr_scanner: ignore (test-only SECURITY DEFINER RPC)
  DELETE FROM public.telegram_evidence_metadata    WHERE organization_id = p_org_id; -- pr_scanner: ignore (test-only SECURITY DEFINER RPC)
  DELETE FROM public.telegram_evidence_categories  WHERE organization_id = p_org_id; -- pr_scanner: ignore (test-only SECURITY DEFINER RPC)
  DELETE FROM public.telegram_evidence_uploads     WHERE organization_id = p_org_id; -- pr_scanner: ignore (test-only SECURITY DEFINER RPC)
  DELETE FROM public.telegram_chat_bindings        WHERE organization_id = p_org_id; -- pr_scanner: ignore (test-only SECURITY DEFINER RPC)
  DELETE FROM public.telegram_binding_tokens       WHERE organization_id = p_org_id; -- pr_scanner: ignore (test-only SECURITY DEFINER RPC)
END;
$$;

-- Ensure execution permissions are granted to authenticated and service_role
REVOKE ALL ON FUNCTION public.get_financial_impact_summary(UUID) FROM PUBLIC, service_role;
GRANT EXECUTE ON FUNCTION public.get_financial_impact_summary(UUID) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.test_cleanup_forensic_data(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.test_cleanup_forensic_data(UUID) TO service_role;

RESET client_min_messages;
