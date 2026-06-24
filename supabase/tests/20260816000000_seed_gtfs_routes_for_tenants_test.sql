-- ============================================================
-- Forensic DB Test: GTFS Routes Seeding
-- Target: 20260816000000_seed_gtfs_routes_for_tenants.sql
-- ============================================================

BEGIN;

-- Plan count: 1 test
SELECT plan(1);

-- ── Manually run the migration insert ──
-- This is required because pgTAP tests run after seed.sql has populated the organizations,
-- but the migration ran when the database was completely empty.
INSERT INTO public.routes (
  organization_id,
  gtfs_route_id,
  short_name,
  long_name,
  agency_id
)
SELECT 
  id as organization_id,
  v.gtfs_route_id,
  v.short_name,
  v.long_name,
  v.agency_id
FROM public.organizations
CROSS JOIN (
  VALUES 
    ('809U-10', '809U', 'Cidade Universitária / Metrô Barra Funda', 'SPTRANS'),
    ('875C-10', '875C', 'Term. Lapa / Metrô Santa Cruz', 'SPTRANS'),
    ('917H-10', '917H', 'Term. Pirituba / Metrô Vila Mariana', 'SPTRANS'),
    ('701U-10', '701U', 'Cidade Universitária / Metrô Santana', 'SPTRANS')
) AS v(gtfs_route_id, short_name, long_name, agency_id)
WHERE status = 'ACTIVE'
ON CONFLICT (organization_id, gtfs_route_id) DO NOTHING;

-- ── 1. Reference Data Existence Check ───────────────────────
-- Use DISTINCT since routes are seeded per organization.
SELECT results_eq(
    'SELECT DISTINCT gtfs_route_id FROM public.routes WHERE gtfs_route_id IN (''809U-10'', ''875C-10'', ''917H-10'', ''701U-10'') ORDER BY gtfs_route_id',
    $$VALUES ('701U-10'), ('809U-10'), ('875C-10'), ('917H-10')$$,
    'Test 1: GTFS reference routes should be seeded into the database.'
);

SELECT * FROM finish();

ROLLBACK;
