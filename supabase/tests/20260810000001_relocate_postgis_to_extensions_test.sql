BEGIN;
SELECT plan(7);

-- =============================================================================
-- Application-side counterpart of the PostGIS relocation (public -> extensions).
--
-- This suite asserts ONLY what the forward migration 20260810000001 controls and
-- what is verifiable BEFORE the platform relocation lands (idempotent, safe while
-- PostGIS still lives in public):
--   - both GPS RPCs carry `search_path = public, extensions` (unqualified ST_*
--     resolves regardless of the extension schema),
--   - the GIST index on operational_zones exists,
--   - both RPCs execute end-to-end with a nil UUID and return their sentinels
--     (proves ST_Distance/ST_DWithin/ST_MakePoint resolve — no "function does not
--     exist"). Post-relocation assertions (public.spatial_ref_sys ABSENT,
--     extensions.spatial_ref_sys PRESENT) are platform-gated and live in the
--     forensic test plan's manual matrix, not here.
-- =============================================================================

-- ── search_path widened to include extensions on both RPCs ───────────────────
SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'check_and_close_execution_autonomously'
      AND array_to_string(p.proconfig, ',') LIKE '%search_path=public, extensions%'
  ),
  'check_and_close_execution_autonomously search_path includes extensions'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'process_gps_for_execution_transitions'
      AND array_to_string(p.proconfig, ',') LIKE '%search_path=public, extensions%'
  ),
  'process_gps_for_execution_transitions search_path includes extensions'
);

-- ── GIST index present (recreated after DROP EXTENSION ... CASCADE) ───────────
SELECT ok(
  to_regclass('public.idx_operational_zones_geog') IS NOT NULL,
  'idx_operational_zones_geog GIST index exists on operational_zones'
);

-- ── RPCs resolve ST_* and return sentinels with a nil UUID ────────────────────
SELECT is(
  (SELECT public.check_and_close_execution_autonomously(
     '00000000-0000-0000-0000-000000000000'::uuid, '__no_such_set__'
   ) ->> 'result'),
  'not_found',
  'autonomous closer resolves ST_* and returns not_found sentinel (INV-26)'
);

SELECT is(
  (SELECT public.process_gps_for_execution_transitions(
     '00000000-0000-0000-0000-000000000000'::uuid, '__no_such_device__', 0, 0
   ) ->> 'result'),
  'no_asset',
  'gps FSM resolves ST_* and returns no_asset sentinel (INV-1)'
);

-- ── Invariants on the catalog (independent of its schema) ─────────────────────
SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'spatial_ref_sys' AND column_name = 'organization_id'
  ),
  'spatial_ref_sys carries NO organization_id column (no tenant data; INV-22 N/A)'
);

SELECT cmp_ok(
  (SELECT count(*) FROM spatial_ref_sys)::int,
  '>=', 8300,
  'spatial_ref_sys row count within expected EPSG bounds'
);

SELECT * FROM finish();
ROLLBACK;
