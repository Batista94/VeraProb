-- =============================================================================
-- Migration: Drain Pending Webhooks RPC
-- =============================================================================

CREATE OR REPLACE FUNCTION public.drain_pending_webhooks(p_org_id uuid, p_limit int)
RETURNS TABLE(id uuid, org_id_out uuid, payload jsonb, endpoint_url text, signing_version int)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_log RECORD;
  v_key_id uuid;
  v_key_version int;
  v_key_status text;
  v_key_retiring_until timestamptz;
BEGIN
  FOR v_log IN 
    SELECT 
      wdl.id AS wdl_id, 
      wdl.organization_id AS wdl_org_id, 
      wdl.payload AS wdl_payload, 
      wdl.signing_key_id AS wdl_key_id, 
      we.url AS we_url, 
      we.organization_id AS endpoint_org_id
    FROM public.webhook_delivery_logs wdl
    JOIN public.webhook_endpoints we ON we.id = wdl.endpoint_id
    WHERE we.is_active = true 
      AND we.deleted_at IS NULL
      AND (
        (wdl.status IN ('PENDING', 'FAILED') AND (wdl.next_attempt_at IS NULL OR wdl.next_attempt_at <= now()))
        OR 
        (wdl.status = 'DELIVERING' AND wdl.next_attempt_at <= now())
      )
      AND (p_org_id IS NULL OR wdl.organization_id = p_org_id)
    ORDER BY wdl.created_at
    FOR UPDATE OF wdl SKIP LOCKED
    LIMIT p_limit
  LOOP
    -- V5 Cross-check
    IF v_log.endpoint_org_id != v_log.wdl_org_id THEN
      INSERT INTO public.system_audit_log (organization_id, event_type, severity, source, payload)
      VALUES (v_log.wdl_org_id, 'CORRUPTION', 'critical', 'rpc', jsonb_build_object('log_id', v_log.wdl_id, 'endpoint_org_id', v_log.endpoint_org_id));
      CONTINUE;
    END IF;

    -- Key Bootstrap (V3)
    IF v_log.wdl_key_id IS NULL THEN
      -- One-active-key-per-org is a partial UNIQUE index (uq_webhook_signing_keys_active,
      -- ON (organization_id) WHERE status = 'active'). Bare DO NOTHING (no target) lets the
      -- planner match that partial index as arbiter without us inferring its predicate.
      -- Idempotent under concurrent SKIP LOCKED drains bootstrapping the same org.
      INSERT INTO public.webhook_signing_keys (organization_id, version, status)
      VALUES (v_log.wdl_org_id, 1, 'active')
      ON CONFLICT DO NOTHING;

      SELECT k.id, k.version, k.status, k.retiring_until 
      INTO v_key_id, v_key_version, v_key_status, v_key_retiring_until
      FROM public.webhook_signing_keys k
      WHERE k.organization_id = v_log.wdl_org_id AND k.status IN ('active', 'retiring', 'revoked')
      ORDER BY k.version DESC LIMIT 1;
    ELSE
      SELECT k.version, k.status, k.retiring_until 
      INTO v_key_version, v_key_status, v_key_retiring_until
      FROM public.webhook_signing_keys k
      WHERE k.id = v_log.wdl_key_id;
      v_key_id := v_log.wdl_key_id;
    END IF;

    -- Check key status
    IF v_key_status = 'revoked' THEN
      UPDATE public.webhook_delivery_logs SET status = 'DEAD', last_error = 'KEY_REVOKED', signing_key_id = v_key_id WHERE webhook_delivery_logs.id = v_log.wdl_id;
      INSERT INTO public.system_audit_log (organization_id, event_type, severity, source, payload)
      VALUES (v_log.wdl_org_id, 'KEY_REVOKED', 'critical', 'rpc', jsonb_build_object('log_id', v_log.wdl_id));
      CONTINUE;
    END IF;

    IF v_key_status = 'retiring' AND v_key_retiring_until IS NOT NULL AND now() > v_key_retiring_until THEN
      UPDATE public.webhook_delivery_logs SET status = 'DEAD', last_error = 'KEY_EXPIRED', signing_key_id = v_key_id WHERE webhook_delivery_logs.id = v_log.wdl_id;
      INSERT INTO public.system_audit_log (organization_id, event_type, severity, source, payload)
      VALUES (v_log.wdl_org_id, 'KEY_EXPIRED', 'critical', 'rpc', jsonb_build_object('log_id', v_log.wdl_id));
      CONTINUE;
    END IF;

    -- Update and Return (Lease of 2 minutes)
    UPDATE public.webhook_delivery_logs 
    SET status = 'DELIVERING', next_attempt_at = now() + interval '2 minutes', signing_key_id = v_key_id 
    WHERE webhook_delivery_logs.id = v_log.wdl_id;

    id := v_log.wdl_id;
    org_id_out := v_log.wdl_org_id;
    payload := v_log.wdl_payload;
    endpoint_url := v_log.we_url;
    signing_version := v_key_version;
    RETURN NEXT;
  END LOOP;
END;
$$;

GRANT EXECUTE ON FUNCTION public.drain_pending_webhooks TO service_role;
