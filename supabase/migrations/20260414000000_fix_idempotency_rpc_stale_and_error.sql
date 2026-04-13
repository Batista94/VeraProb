-- =============================================================================
-- Migration: 20260414000000 — Fix Idempotency RPC Stale Threshold & Error Caching
-- 
-- BUG FIXES:
--   1. p_stale_threshold_min was being passed to try_acquire_idempotency_key 
--      but ignored in the INSERT/UPDATE statements.
--   2. fail_idempotency_key did not support p_response_body, preventing
--      the caching of DomainException/4xx messages.
-- =============================================================================

-- ── 1. Fix try_acquire_idempotency_key ────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.try_acquire_idempotency_key(
  p_id                    TEXT,
  p_user_id               UUID,
  p_command_path          TEXT,
  p_organization_id       UUID,
  p_stale_threshold_min   INT DEFAULT 5
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  v_existing RECORD;
  v_inserted BOOLEAN;
  v_stale_threshold INTERVAL;
BEGIN
  -- Step 1: Check if key already exists.
  SELECT status, response_code, response_body, created_at_utc, completed_at_utc,
         COALESCE(stale_threshold_minutes, 5) AS stale_threshold_minutes
    INTO v_existing
    FROM public.idempotency_keys
   WHERE id = p_id AND user_id = p_user_id
   LIMIT 1;

  -- Key found.
  IF FOUND THEN
    IF v_existing.status = 'completed' THEN
      RETURN jsonb_build_object(
        'hit', true,
        'status', 'completed',
        'response_code', v_existing.response_code,
        'response_body', v_existing.response_body,
        'completed_at_utc', v_existing.completed_at_utc
      );
    ELSIF v_existing.status = 'processing' THEN
      -- Stale Detection 
      v_stale_threshold := (v_existing.stale_threshold_minutes || ' minutes')::INTERVAL;

      IF NOW() - v_existing.created_at_utc > v_stale_threshold THEN
        UPDATE public.idempotency_keys
           SET status = 'processing',
               response_code = NULL,
               response_body = NULL,
               completed_at_utc = NULL,
               created_at_utc = NOW(),
               stale_threshold_minutes = p_stale_threshold_min -- [FIX] Update on reclaim
         WHERE id = p_id AND user_id = p_user_id AND status = 'processing';

        RETURN jsonb_build_object(
          'hit', false,
          'status', 'processing',
          'acquired', true,
          'reclaimed_from_stale', true
        );
      END IF;

      RAISE EXCEPTION
        'IdempotencyProcessingException: Command is already being processed. '
        'key: %, command: %, user_id: %',
        p_id, p_command_path, p_user_id
      USING ERRCODE = 'unique_violation',
            DETAIL = 'Another request is processing this command. Retry or poll status.';
    ELSIF v_existing.status = 'error' THEN
      -- Reset error -> processing
      UPDATE public.idempotency_keys
         SET status = 'processing',
             response_code = NULL,
             response_body = NULL,
             completed_at_utc = NULL,
             stale_threshold_minutes = p_stale_threshold_min -- [FIX] Update on retry
       WHERE id = p_id AND user_id = p_user_id AND status = 'error';
      RETURN jsonb_build_object(
        'hit', false,
        'status', 'processing',
        'acquired', true
      );
    END IF;
  END IF;

  -- Step 2: Try to register as 'processing' (ON CONFLICT DO NOTHING)
  INSERT INTO public.idempotency_keys (
    id, user_id, command_path, organization_id, status, created_at_utc, 
    stale_threshold_minutes -- [FIX] Include in INSERT
  )
  VALUES (
    p_id, p_user_id, p_command_path, p_organization_id, 'processing', NOW(), 
    p_stale_threshold_min
  )
  ON CONFLICT (id, user_id) DO NOTHING;

  GET DIAGNOSTICS v_inserted = ROW_COUNT;

  IF v_inserted = 0 THEN
    -- Race condition re-check
    SELECT status, created_at_utc, COALESCE(stale_threshold_minutes, 5) AS stale_threshold_minutes
      INTO v_existing
      FROM public.idempotency_keys
     WHERE id = p_id AND user_id = p_user_id
     LIMIT 1;

    IF FOUND AND v_existing.status = 'completed' THEN
      RETURN jsonb_build_object(
        'hit', true,
        'status', 'completed',
        'response_code', v_existing.response_code,
        'response_body', v_existing.response_body,
        'completed_at_utc', v_existing.completed_at_utc
      );
    ELSIF FOUND AND v_existing.status = 'processing' THEN
      v_stale_threshold := (v_existing.stale_threshold_minutes || ' minutes')::INTERVAL;
      IF NOW() - v_existing.created_at_utc > v_stale_threshold THEN
        UPDATE public.idempotency_keys
           SET status = 'processing',
               response_code = NULL,
               response_body = NULL,
               completed_at_utc = NULL,
               created_at_utc = NOW(),
               stale_threshold_minutes = p_stale_threshold_min -- [FIX] Update on reclaim
         WHERE id = p_id AND user_id = p_user_id AND status = 'processing';

        RETURN jsonb_build_object(
          'hit', false,
          'status', 'processing',
          'acquired', true,
          'reclaimed_from_stale', true
        );
      END IF;
    END IF;

    RAISE EXCEPTION
      'IdempotencyProcessingException: Command is already being processed (race condition). '
      'key: %, command: %, user_id: %',
      p_id, p_command_path, p_user_id
    USING ERRCODE = 'unique_violation';
  END IF;

  RETURN jsonb_build_object(
    'hit', false,
    'status', 'processing',
    'acquired', true
  );
END;
$$;

-- ── 2. Fix fail_idempotency_key ──────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fail_idempotency_key(
  p_id            TEXT,
  p_user_id       UUID,
  p_response_code INT,
  p_response_body JSONB DEFAULT NULL -- [FIX] Added parameter to cache error messages
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE public.idempotency_keys
     SET status = 'error',
         response_code = p_response_code,
         response_body = p_response_body, -- [FIX] Record the error message/payload
         completed_at_utc = NOW()
   WHERE id = p_id
     AND user_id = p_user_id
     AND status = 'processing';

  IF NOT FOUND THEN
    RAISE WARNING 'fail_idempotency_key: no processing key found for id=%, user_id=%', p_id, p_user_id;
  END IF;
END;
$$;
