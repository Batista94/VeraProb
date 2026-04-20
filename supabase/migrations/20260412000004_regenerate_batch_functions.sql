-- ============================================================
-- veraprob — Batch Update RPC Functions (hand-written)
-- ============================================================
-- These functions provide atomic batch updates with optimistic
-- locking. They are hand-written (NOT auto-generated) to avoid
-- PL/pgSQL format() vs RAISE placeholder conflicts.
--
-- To add a new column: add a COALESCE line in both functions.
-- ============================================================

-- ── 1. Batch Update Vehicles ────────────────────────────────

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

-- ── 2. Batch Update Contracts ───────────────────────────────

CREATE OR REPLACE FUNCTION public.batch_update_contracts(
  p_updates JSONB  -- [{id, version, name?, contractor_name?, ...}, ...]
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
      description = COALESCE(spec->>'description', description),
      status = COALESCE(spec->>'status', status),
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

-- ── 3. Comments ─────────────────────────────────────────────

COMMENT ON FUNCTION public.batch_update_vehicles(JSONB) IS
  'Atomic batch update for vehicles with optimistic locking. All-or-nothing: if ANY vehicle has a stale version, the entire batch is rolled back.';

COMMENT ON FUNCTION public.batch_update_contracts(JSONB) IS
  'Atomic batch update for contracts with optimistic locking. All-or-nothing: if ANY contract has a stale version, the entire batch is rolled back.';
