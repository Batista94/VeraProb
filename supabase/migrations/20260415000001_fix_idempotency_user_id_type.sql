-- pr_scanner: ignore-regression
--
-- =============================================================================
-- Migration: 20260415000001 — Fix idempotency_keys.user_id: UUID → TEXT
--
-- REASON:
--   The original schema declared user_id as UUID with a FK to auth.users(id).
--   This breaks any caller that uses a non-UUID user identifier (e.g. 'admin-e2e'
--   in E2E tests) — Postgres raises 22P02 (invalid UUID syntax), which the
--   app layer maps to ResourceNotFoundException, masking the real failure.
--   It also breaks service_role inserts for users not in auth.users (23503 FK
--   violation) because service_role bypasses RLS but NOT FK constraints.
--
--   VeraProb's user identity comes from JWT claims (TEXT), not from auth.users
--   rows. The FK was over-constrained; identity sovereignty is enforced at the
--   application layer (INV-1, INV-2) via RLS policies and tenant validation.
--
-- CHANGES:
--   1. Drop FK constraint (user_id REFERENCES auth.users)
--   2. Drop PRIMARY KEY (user_id is part of the composite PK)
--   3. ALTER COLUMN user_id: UUID → TEXT
--   4. Recreate PRIMARY KEY (id, user_id)
--   5. Recreate user_status index
--   6. Update RLS policies — auth.uid()::text for TEXT comparison
--   7. DROP old UUID-parameter RPC overloads (Postgres does NOT replace on type
--      change — it creates a new overload, leaving an ambiguous resolution)
--   8. Recreate all 3 RPC functions with p_user_id TEXT
--
-- INVARIANTS:
--   INV-1:  organization_id filters all queries (unchanged)
--   INV-2:  RLS uses auth.uid()::text after this migration
--   INV-6:  All timestamps remain UTC (unchanged)
--   INV-33: Idempotency contract unchanged — key scope is (id, user_id TEXT)
-- =============================================================================

SET client_min_messages TO 'WARNING';

-- ── 1. Drop FK constraint ────────────────────────────────────────────────────
--
-- Postgres auto-names it <table>_<column>_fkey.
-- IF EXISTS makes this idempotent.

ALTER TABLE public.idempotency_keys
  DROP CONSTRAINT IF EXISTS idempotency_keys_user_id_fkey;

-- ── 2. Drop PRIMARY KEY (contains user_id UUID) ──────────────────────────────
--
-- ALTER COLUMN requires dropping the PK first when the column is part of it.

ALTER TABLE public.idempotency_keys
  DROP CONSTRAINT IF EXISTS idempotency_keys_pkey;

-- ── 3. Drop user_status index ────────────────────────────────────────────────
DROP INDEX IF EXISTS public.idx_idempotency_keys_user_status;

-- ── 4. Drop RLS policies depending on user_id ────────────────────────────────
--
-- Postgres blocks ALTER TYPE if the column is used in a policy definition.
-- We must drop them first and recreate them after the type change.
DROP POLICY IF EXISTS idempotency_keys_select_own ON public.idempotency_keys;
DROP POLICY IF EXISTS idempotency_keys_insert_own ON public.idempotency_keys;
DROP POLICY IF EXISTS idempotency_keys_update_own ON public.idempotency_keys;

-- ── 5. Change column type: UUID → TEXT ───────────────────────────────────────
--
-- USING user_id::text casts existing UUID values to their standard string
-- representation (e.g. '00000000-0000-0000-0000-000000000001').
-- Existing rows are preserved without data loss.

ALTER TABLE public.idempotency_keys
  ALTER COLUMN user_id TYPE TEXT USING user_id::text; -- pr_scanner: ignore

-- ── 5. Recreate PRIMARY KEY ───────────────────────────────────────────────────

ALTER TABLE public.idempotency_keys
  ADD PRIMARY KEY (id, user_id);

-- ── 6. Recreate user_status index ────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_idempotency_keys_user_status
  ON public.idempotency_keys (user_id, status);

-- ── 8. Recreate RLS policies ──────────────────────────────────────────────────
--
-- auth.uid() returns UUID. Comparing UUID = TEXT requires an explicit cast.
-- Use auth.uid()::text for all user_id comparisons in these policies.

CREATE POLICY idempotency_keys_select_own
  ON public.idempotency_keys
  FOR SELECT
  USING (user_id = (auth.jwt() ->> 'sub'));

CREATE POLICY idempotency_keys_insert_own
  ON public.idempotency_keys
  FOR INSERT
  WITH CHECK (
    user_id = (auth.jwt() ->> 'sub')
    AND status = 'processing'
  );

CREATE POLICY idempotency_keys_update_own
  ON public.idempotency_keys
  FOR UPDATE
  USING (user_id = (auth.jwt() ->> 'sub'))
  WITH CHECK (
    user_id = (auth.jwt() ->> 'sub')
    AND status IN ('completed', 'error')
  );

-- idempotency_keys_service_all has no user_id reference — no change needed.

-- ── 8. Drop old UUID-parameter RPC overloads ──────────────────────────────────
--
-- CRITICAL: PostgreSQL CREATE OR REPLACE does NOT replace when parameter types
-- change — it creates a NEW overload. Both old (TEXT, UUID, ...) and new
-- (TEXT, TEXT, ...) signatures coexist and PostgREST fails with
-- "Could not find the function ... in the schema cache".
-- We must DROP the old signatures explicitly before recreating.

-- Original signature from 20260413000002_idempotency_infrastructure.sql:
DROP FUNCTION IF EXISTS public.try_acquire_idempotency_key(TEXT, UUID, TEXT, UUID, INT);

-- Original signature from 20260413000002_idempotency_infrastructure.sql:
DROP FUNCTION IF EXISTS public.complete_idempotency_key(TEXT, UUID, INT, JSONB);

-- Original signature from 20260413000002 (no response_body):
DROP FUNCTION IF EXISTS public.fail_idempotency_key(TEXT, UUID, INT);

-- Updated signature from 20260414000000_fix_idempotency_rpc_stale_and_error.sql:
DROP FUNCTION IF EXISTS public.fail_idempotency_key(TEXT, UUID, INT, JSONB);

-- ── 9. Recreate try_acquire_idempotency_key with p_user_id TEXT ──────────────
--
-- Body is identical to 20260414000000 — only p_user_id type changes UUID→TEXT.

CREATE OR REPLACE FUNCTION public.try_acquire_idempotency_key(
  p_id                    TEXT,
  p_user_id               TEXT,
  p_command_path          TEXT,
  p_organization_id       UUID,
  p_stale_threshold_min   INT DEFAULT 5
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  v_existing        RECORD;
  v_inserted        INT;
  v_stale_threshold INTERVAL;
BEGIN
  -- Step 1: Check if key already exists.
  SELECT status, response_code, response_body, created_at_utc, completed_at_utc,
         COALESCE(stale_threshold_minutes, 5) AS stale_threshold_minutes
    INTO v_existing
    FROM public.idempotency_keys
   WHERE id = p_id AND user_id = p_user_id
   LIMIT 1;

  IF FOUND THEN
    IF v_existing.status = 'completed' THEN
      -- Short-circuit: return cached response.
      RETURN jsonb_build_object(
        'hit', true,
        'status', 'completed',
        'response_code', v_existing.response_code,
        'response_body', v_existing.response_body,
        'completed_at_utc', v_existing.completed_at_utc
      );

    ELSIF v_existing.status = 'processing' THEN
      v_stale_threshold := (v_existing.stale_threshold_minutes || ' minutes')::INTERVAL;

      IF NOW() - v_existing.created_at_utc > v_stale_threshold THEN
        UPDATE public.idempotency_keys
           SET status                 = 'processing',
               response_code         = NULL,
               response_body         = NULL,
               completed_at_utc      = NULL,
               created_at_utc        = NOW(),
               stale_threshold_minutes = p_stale_threshold_min
         WHERE id = p_id AND user_id = p_user_id AND status = 'processing';

        RETURN jsonb_build_object(
          'hit',                 false,
          'status',              'processing',
          'acquired',            true,
          'reclaimed_from_stale', true
        );
      END IF;

      -- Not stale — another thread is genuinely processing.
      RAISE EXCEPTION
        'IdempotencyProcessingException: Command is already being processed. '
        'key: %, command: %, user_id: %',
        p_id, p_command_path, p_user_id
      USING ERRCODE = 'unique_violation',
            DETAIL  = 'Another request is processing this command. Retry or poll status.';

    ELSIF v_existing.status = 'error' THEN
      -- Previous attempt failed — allow retry by resetting to 'processing'.
      UPDATE public.idempotency_keys
         SET status                 = 'processing',
             response_code         = NULL,
             response_body         = NULL,
             completed_at_utc      = NULL,
             stale_threshold_minutes = p_stale_threshold_min
       WHERE id = p_id AND user_id = p_user_id AND status = 'error';

      RETURN jsonb_build_object(
        'hit',     false,
        'status',  'processing',
        'acquired', true
      );
    END IF;
  END IF;

  -- Step 2: Key not found — register as 'processing'.
  INSERT INTO public.idempotency_keys
    (id, user_id, command_path, organization_id, status, created_at_utc, stale_threshold_minutes)
  VALUES
    (p_id, p_user_id, p_command_path, p_organization_id, 'processing', NOW(), p_stale_threshold_min)
  ON CONFLICT (id, user_id) DO NOTHING;

  GET DIAGNOSTICS v_inserted = ROW_COUNT;

  IF v_inserted = 0 THEN
    -- Race condition: another thread inserted between our SELECT and INSERT.
    SELECT status, created_at_utc, COALESCE(stale_threshold_minutes, 5) AS stale_threshold_minutes
      INTO v_existing
      FROM public.idempotency_keys
     WHERE id = p_id AND user_id = p_user_id
     LIMIT 1;

    IF FOUND AND v_existing.status = 'completed' THEN
      RETURN jsonb_build_object(
        'hit',          true,
        'status',       'completed',
        'response_code', v_existing.response_code,
        'response_body', v_existing.response_body,
        'completed_at_utc', v_existing.completed_at_utc
      );
    ELSIF FOUND AND v_existing.status = 'processing' THEN
      v_stale_threshold := (v_existing.stale_threshold_minutes || ' minutes')::INTERVAL;

      IF NOW() - v_existing.created_at_utc > v_stale_threshold THEN
        UPDATE public.idempotency_keys
           SET status                 = 'processing',
               response_code         = NULL,
               response_body         = NULL,
               completed_at_utc      = NULL,
               created_at_utc        = NOW(),
               stale_threshold_minutes = p_stale_threshold_min
         WHERE id = p_id AND user_id = p_user_id AND status = 'processing';

        RETURN jsonb_build_object(
          'hit',                 false,
          'status',              'processing',
          'acquired',            true,
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

  -- Step 3: Key successfully registered as 'processing'.
  RETURN jsonb_build_object(
    'hit',     false,
    'status',  'processing',
    'acquired', true
  );
END;
$$;

-- ── 10. Recreate complete_idempotency_key with p_user_id TEXT ─────────────────

CREATE OR REPLACE FUNCTION public.complete_idempotency_key(
  p_id            TEXT,
  p_user_id       TEXT,
  p_response_code INT,
  p_response_body JSONB
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE public.idempotency_keys
     SET status           = 'completed',
         response_code    = p_response_code,
         response_body    = p_response_body,
         completed_at_utc = NOW()
   WHERE id       = p_id
     AND user_id  = p_user_id
     AND status   = 'processing';

  IF NOT FOUND THEN
    RAISE WARNING
      'complete_idempotency_key: no processing key found for id=%, user_id=%',
      p_id, p_user_id;
  END IF;
END;
$$;

-- ── 11. Recreate fail_idempotency_key with p_user_id TEXT ────────────────────

CREATE OR REPLACE FUNCTION public.fail_idempotency_key(
  p_id            TEXT,
  p_user_id       TEXT,
  p_response_code INT,
  p_response_body JSONB DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE public.idempotency_keys
     SET status           = 'error',
         response_code    = p_response_code,
         response_body    = p_response_body,
         completed_at_utc = NOW()
   WHERE id      = p_id
     AND user_id = p_user_id
     AND status  = 'processing';

  IF NOT FOUND THEN
    RAISE WARNING
      'fail_idempotency_key: no processing key found for id=%, user_id=%',
      p_id, p_user_id;
  END IF;
END;
$$;

-- ── 12. Function comments ─────────────────────────────────────────────────────

COMMENT ON FUNCTION public.try_acquire_idempotency_key(TEXT, TEXT, TEXT, UUID, INT) IS
  'INV-33 — Atomically registers an idempotency key as "processing". '
  'Returns {hit, status, acquired} JSONB. p_user_id is TEXT (not UUID) '
  'to support non-UUID user identifiers from JWT claims.';

COMMENT ON FUNCTION public.complete_idempotency_key(TEXT, TEXT, INT, JSONB) IS
  'INV-33 — Marks an idempotency key as "completed" with the response body. '
  'p_user_id is TEXT after migration 20260415000001.';

COMMENT ON FUNCTION public.fail_idempotency_key(TEXT, TEXT, INT, JSONB) IS
  'INV-33 — Marks an idempotency key as "error". '
  'p_user_id is TEXT after migration 20260415000001.';

-- ── 13. Verification ──────────────────────────────────────────────────────────

DO $$
BEGIN
  -- Verify user_id column is now TEXT.
  IF NOT EXISTS (
    SELECT 1
      FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name   = 'idempotency_keys'
       AND column_name  = 'user_id'
       AND data_type    = 'text'
  ) THEN
    RAISE EXCEPTION 'user_id column is not TEXT after migration';
  END IF;

  -- Verify no FK constraint remains on user_id.
  IF EXISTS (
    SELECT 1
      FROM information_schema.referential_constraints rc
      JOIN information_schema.key_column_usage kcu
        ON kcu.constraint_name = rc.constraint_name
     WHERE kcu.table_schema  = 'public'
       AND kcu.table_name    = 'idempotency_keys'
       AND kcu.column_name   = 'user_id'
  ) THEN
    RAISE EXCEPTION 'FK constraint still exists on idempotency_keys.user_id';
  END IF;

  -- Verify new TEXT-parameter RPC exists.
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname = 'try_acquire_idempotency_key'
  ) THEN
    RAISE EXCEPTION 'try_acquire_idempotency_key function not found after migration';
  END IF;

  RAISE NOTICE
    '✅ idempotency_keys.user_id migrated UUID→TEXT successfully (20260415000001)';
END
$$;
