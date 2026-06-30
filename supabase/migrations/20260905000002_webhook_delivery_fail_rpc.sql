-- =============================================================================
-- Migration: Webhook Delivery Fail RPC
-- =============================================================================

CREATE OR REPLACE FUNCTION public.webhook_delivery_fail(p_log_id uuid, p_error text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_attempt int;
  v_next_attempt timestamptz;
BEGIN
  -- We select attempt_count for the current log. Since only service_role (edge function) calls this,
  -- and it's sequential per log, a simple select is sufficient, but we can lock it to be safe.
  SELECT attempt_count INTO v_attempt 
  FROM public.webhook_delivery_logs 
  WHERE id = p_log_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  v_attempt := v_attempt + 1;

  IF v_attempt >= 8 THEN
    UPDATE public.webhook_delivery_logs 
    SET 
      status = 'DEAD', 
      attempt_count = v_attempt, 
      next_attempt_at = NULL, 
      last_error = left(p_error, 200)
    WHERE id = p_log_id;
  ELSE
    -- Calculate backoff: LEAST(6 hours, 30s * 2^(attempt_count)) + jitter
    -- v_attempt is already incremented, so first retry (v_attempt=1) waits 30s * 2^1 = 60s
    -- Wait, the prompt said: 30s * power(2, attempt_count). 
    -- If attempt_count was 0, it became 1.
    -- power(2, v_attempt) = 2. 30 * 2 = 60s.
    v_next_attempt := now() + LEAST(interval '6 hours', interval '30 seconds' * power(2, v_attempt)) + (random() * interval '15 seconds');

    UPDATE public.webhook_delivery_logs 
    SET 
      status = 'FAILED', 
      attempt_count = v_attempt, 
      next_attempt_at = v_next_attempt, 
      last_error = left(p_error, 200)
    WHERE id = p_log_id;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.webhook_delivery_fail TO service_role;
