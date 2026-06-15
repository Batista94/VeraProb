-- ============================================================
-- Forensic DB Test: GTFS Routes Seeding
-- Target: 20260816000000_seed_gtfs_routes_for_tenants.sql
-- ============================================================

BEGIN;

-- Plan count: 1 test
SELECT plan(1);

-- ── 1. Reference Data Existence Check ───────────────────────
-- Ensure the 4 base GTFS routes exist in the system for testing
-- and development. This bypasses the need for the Dart Seeder
-- to perform an invalid insert into a read-only table.
SELECT results_eq(
    'SELECT gtfs_route_id FROM public.routes WHERE gtfs_route_id IN (''809U-10'', ''875C-10'', ''917H-10'', ''701U-10'') ORDER BY gtfs_route_id',
    $$VALUES ('701U-10'), ('809U-10'), ('875C-10'), ('917H-10')$$,
    'Test 1: GTFS reference routes should be seeded into the database.'
);

SELECT * FROM finish();

ROLLBACK;
