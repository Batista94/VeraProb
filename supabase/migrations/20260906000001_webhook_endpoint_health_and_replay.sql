-- =============================================================================
-- Migration: Webhook Health View & Manual Replay RPC
-- INV-2: Security Invoker
-- INV-1: Tenant Validation
-- =============================================================================

-- 1. View: v_webhook_endpoint_health
CREATE OR REPLACE VIEW public.v_webhook_endpoint_health
WITH (security_invoker = true) AS
SELECT
  e.id,
  e.organization_id,
  e.url,
  e.is_active,
  e.last_kick_at,
  e.created_at,
  COUNT(l.id) AS total_logs,
  COUNT(l.id) FILTER (WHERE l.status = 'PENDING') AS pending_count,
  COUNT(l.id) FILTER (WHERE l.status = 'DELIVERING') AS delivering_count,
  COUNT(l.id) FILTER (WHERE l.status = 'SUCCESS') AS success_count,
  COUNT(l.id) FILTER (WHERE l.status = 'FAILED') AS failed_count,
  COUNT(l.id) FILTER (WHERE l.status = 'DEAD') AS dead_count,
  MAX(l.dispatched_at) AS last_dispatched_at
FROM
  public.webhook_endpoints e
LEFT JOIN
  public.webhook_delivery_logs l ON e.id = l.endpoint_id
WHERE
  e.deleted_at IS NULL
GROUP BY
  e.id, e.organization_id, e.url, e.is_active, e.last_kick_at, e.created_at;

-- Grants
GRANT SELECT ON public.v_webhook_endpoint_health TO authenticated;

-- 2. RPC: webhook_manual_replay
CREATE OR REPLACE FUNCTION public.webhook_manual_replay(p_log_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_org_id UUID;
  v_role TEXT;
  v_log_record public.webhook_delivery_logs%ROWTYPE;
  v_endpoint_record public.webhook_endpoints%ROWTYPE;
BEGIN
  -- 1. Auth & IAM (INV-1)
  v_org_id := (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid;
  v_role := auth.jwt() -> 'app_metadata' ->> 'role';

  IF v_org_id IS NULL OR v_role IS NULL THEN
    RAISE EXCEPTION 'Not authenticated or missing claims' USING ERRCODE = 'unauthenticated';
  END IF;

  IF v_role != 'TENANT_ADMIN' THEN
    RAISE EXCEPTION 'Insufficient permissions' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- 2. Fetch Log & Validate Ownership (INV-1 / INV-26 Anti-Oracle)
  SELECT * INTO v_log_record
  FROM public.webhook_delivery_logs
  WHERE id = p_log_id;

  IF NOT FOUND OR v_log_record.organization_id != v_org_id THEN
    RAISE EXCEPTION 'Webhook delivery log not found' USING ERRCODE = 'not_found';
  END IF;

  -- 3. Validate Status
  IF v_log_record.status NOT IN ('FAILED', 'DEAD') THEN
    RAISE EXCEPTION 'Can only replay FAILED or DEAD logs' USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- 4. Rate Limiting (30s minimum interval)
  SELECT * INTO v_endpoint_record
  FROM public.webhook_endpoints
  WHERE id = v_log_record.endpoint_id
  FOR UPDATE; -- Lock for concurrency

  IF v_endpoint_record.last_kick_at IS NOT NULL AND v_endpoint_record.last_kick_at > NOW() - INTERVAL '30 seconds' THEN
    RAISE EXCEPTION 'Rate limit exceeded: Please wait 30 seconds between replays' USING ERRCODE = 'rate_limit_exceeded';
  END IF;

  -- 5. Update Log to PENDING
  UPDATE public.webhook_delivery_logs
  SET
    status = 'PENDING',
    attempt_count = 0,
    next_attempt_at = NOW(),
    last_error = NULL
  WHERE id = p_log_id;

  -- 6. Update Endpoint rate limit
  UPDATE public.webhook_endpoints
  SET last_kick_at = NOW()
  WHERE id = v_log_record.endpoint_id;

  -- Note: The dispatcher edge function should be called asynchronously by the Dart client
  -- after this RPC returns successfully.
END;
$$;

GRANT EXECUTE ON FUNCTION public.webhook_manual_replay(UUID) TO authenticated;
