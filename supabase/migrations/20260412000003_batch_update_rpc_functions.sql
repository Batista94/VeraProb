-- ============================================================
-- veraprob — Batch Update RPC Functions for Atomic Optimistic Locking
-- ============================================================
-- REASON:
--   Supabase Dart client does not expose explicit transactions (BEGIN/COMMIT).
--   To guarantee atomicity for batch updates (all-or-nothing), we use
--   PostgreSQL stored procedures. Each function runs in an implicit transaction
--   and rolls back entirely if ANY entity has a stale version.
--
-- STRATEGY:
--   1. Phase 1: Verify ALL versions match BEFORE any write
--   2. Phase 2: Execute updates with optimistic lock WHERE clause
--   3. GET DIAGNOSTICS: If ANY update affects 0 rows → RAISE EXCEPTION → ROLLBACK
--
-- SECURITY:
--   - No dynamic SQL — all column references are hardcoded
--   - Type-safe UUID and BIGINT casting
--   - P0001 error code → maps to ConflictException in Dart
-- ============================================================

-- ── 1. Batch Update Vehicles ─────────────────────────────────

CREATE OR REPLACE FUNCTION public.batch_update_vehicles(
  p_updates JSONB  -- [{id, version, plate?, model?, capacity?, status?}, ...]
) RETURNS JSONB AS $$
DECLARE
  spec JSONB;
  current_version BIGINT;
  v_rows_affected INT;
BEGIN
  -- Phase 1: Verify ALL versions BEFORE any write
  FOR spec IN SELECT * FROM jsonb_array_elements(p_updates) LOOP
    SELECT version INTO current_version
    FROM vehicles
    WHERE id = (spec->>'id')::UUID;

    IF current_version IS NULL OR current_version != (spec->>'version')::BIGINT THEN
      RAISE EXCEPTION
        'Batch conflict: vehicle % is stale (expected version %, got %)',
        spec->>'id',
        spec->>'version',
        current_version
        USING ERRCODE = 'P0001';
    END IF;
  END LOOP;

  -- Phase 2: Execute updates atomically (implicit transaction)
  -- Each UPDATE has an optimistic lock WHERE clause for TOCTOU protection.
  FOR spec IN SELECT * FROM jsonb_array_elements(p_updates) LOOP
    UPDATE vehicles SET
      plate = COALESCE(spec->>'plate', plate),
      model = COALESCE(spec->>'model', model),
      capacity = COALESCE((spec->>'capacity')::INT, capacity),
      status = COALESCE(spec->>'status', status)
    WHERE id = (spec->>'id')::UUID
      AND version = (spec->>'version')::BIGINT;

    GET DIAGNOSTICS v_rows_affected = ROW_COUNT;
    IF v_rows_affected = 0 THEN
      RAISE EXCEPTION
        'Batch conflict: vehicle % was modified concurrently',
        spec->>'id'
        USING ERRCODE = 'P0001';
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'updated_count', jsonb_array_length(p_updates)
  );
END;
$$ LANGUAGE plpgsql;

-- RLS: Only authenticated users from the correct org can batch-update
-- (The function inherits caller's RLS context — no BYPASSRLS needed)
GRANT EXECUTE ON FUNCTION public.batch_update_vehicles(JSONB) TO authenticated;

-- ── 2. Batch Update Contracts ────────────────────────────────

CREATE OR REPLACE FUNCTION public.batch_update_contracts(
  p_updates JSONB  -- [{id, version, name?, contractor_name?, status?, ...}, ...]
) RETURNS JSONB AS $$
DECLARE
  spec JSONB;
  current_version BIGINT;
  v_rows_affected INT;
BEGIN
  -- Phase 1: Verify ALL versions BEFORE any write
  FOR spec IN SELECT * FROM jsonb_array_elements(p_updates) LOOP
    SELECT version INTO current_version
    FROM contracts
    WHERE id = (spec->>'id')::UUID;

    IF current_version IS NULL OR current_version != (spec->>'version')::BIGINT THEN
      RAISE EXCEPTION
        'Batch conflict: contract % is stale (expected version %, got %)',
        spec->>'id',
        spec->>'version',
        current_version
        USING ERRCODE = 'P0001';
    END IF;
  END LOOP;

  -- Phase 2: Execute updates atomically (implicit transaction)
  FOR spec IN SELECT * FROM jsonb_array_elements(p_updates) LOOP
    UPDATE contracts SET
      name = COALESCE(spec->>'name', name),
      contractor_name = COALESCE(spec->>'contractor_name', contractor_name),
      description = COALESCE((spec->>'description')::TEXT, description),
      status = COALESCE(spec->>'status', status),
      activated_at_utc = COALESCE(
        NULLIF(spec->>'activated_at_utc', 'null')::TIMESTAMPTZ,
        activated_at_utc
      ),
      closed_at_utc = COALESCE(
        NULLIF(spec->>'closed_at_utc', 'null')::TIMESTAMPTZ,
        closed_at_utc
      ),
      closed_by_user_id = COALESCE(spec->>'closed_by_user_id', closed_by_user_id),
      close_reason = COALESCE(spec->>'close_reason', close_reason),
      financial_ceiling_cents = COALESCE(
        NULLIF(spec->>'financial_ceiling_cents', 'null')::BIGINT,
        financial_ceiling_cents
      ),
      penalty_multiplier = COALESCE(
        NULLIF(spec->>'penalty_multiplier', 'null')::DOUBLE PRECISION,
        penalty_multiplier
      ),
      latitude = COALESCE(
        NULLIF(spec->>'latitude', 'null')::DOUBLE PRECISION,
        latitude
      ),
      longitude = COALESCE(
        NULLIF(spec->>'longitude', 'null')::DOUBLE PRECISION,
        longitude
      )
    WHERE id = (spec->>'id')::UUID
      AND version = (spec->>'version')::BIGINT;

    GET DIAGNOSTICS v_rows_affected = ROW_COUNT;
    IF v_rows_affected = 0 THEN
      RAISE EXCEPTION
        'Batch conflict: contract % was modified concurrently',
        spec->>'id'
        USING ERRCODE = 'P0001';
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'updated_count', jsonb_array_length(p_updates)
  );
END;
$$ LANGUAGE plpgsql;

-- RLS: Only authenticated users from the correct org can batch-update
GRANT EXECUTE ON FUNCTION public.batch_update_contracts(JSONB) TO authenticated;

-- ── 3. Comments ──────────────────────────────────────────────

COMMENT ON FUNCTION public.batch_update_vehicles(JSONB) IS
  'Atomic batch update for vehicles with optimistic locking. All-or-nothing: if ANY vehicle has a stale version, the entire batch is rolled back. Input: JSONB array of {id, version, plate?, model?, capacity?, status?}.';

COMMENT ON FUNCTION public.batch_update_contracts(JSONB) IS
  'Atomic batch update for contracts with optimistic locking. All-or-nothing: if ANY contract has a stale version, the entire batch is rolled back. Input: JSONB array of {id, version, name?, contractor_name?, status?, ...}.';
