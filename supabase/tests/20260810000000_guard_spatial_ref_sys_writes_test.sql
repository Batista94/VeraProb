BEGIN;
SELECT plan(7);

-- =============================================================================
-- Guard + invariants for public.spatial_ref_sys (PostGIS catalog).
--
-- The advisor `rls_disabled_in_public` cannot be cleared at the postgres tier
-- (table owned by supabase_admin: RLS/REVOKE blocked). The interim control is a
-- BEFORE statement-level trigger that blocks anon/authenticated mutations.
-- Root-cause fix = relocate PostGIS to `extensions` (platform/supabase_admin).
-- =============================================================================

-- ── Structure: guard function + trigger exist ────────────────────────────────
SELECT has_function(
  'public', 'guard_spatial_ref_sys_writes', ARRAY[]::text[],
  'guard_spatial_ref_sys_writes() trigger function exists'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgrelid = 'public.spatial_ref_sys'::regclass
      AND tgname  = 'guard_spatial_ref_sys_writes_trg'
      AND NOT tgisinternal
  ),
  'guard trigger is attached to public.spatial_ref_sys'
);

-- ── Behaviour: anon mutations are BLOCKED (42501) ────────────────────────────
-- throws_ok runs as the test role (postgres) and executes the DO block, which
-- switches to anon ONLY for the inner statement so the guard's role check fires.
SELECT throws_ok(
  $$ DO $d$ BEGIN SET LOCAL ROLE anon;
       DELETE FROM public.spatial_ref_sys WHERE srid = -99999; END $d$ $$,
  '42501',
  NULL,
  'anon DELETE on spatial_ref_sys is blocked by the guard'
);
RESET ROLE;

SELECT throws_ok(
  $$ DO $d$ BEGIN SET LOCAL ROLE authenticated;
       UPDATE public.spatial_ref_sys SET auth_name = auth_name WHERE srid = -99999; END $d$ $$,
  '42501',
  NULL,
  'authenticated UPDATE on spatial_ref_sys is blocked by the guard'
);
RESET ROLE;

-- ── Inverse: privileged role passes the guard (PostGIS maintenance intact) ────
SELECT lives_ok(
  $$ DELETE FROM public.spatial_ref_sys WHERE srid = -99999 $$,
  'privileged role (postgres) is NOT blocked by the guard (0-row no-op)'
);

-- ── Invariants: reference catalog, never tenant data ─────────────────────────
SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'spatial_ref_sys'
      AND column_name  = 'organization_id'
  ),
  'spatial_ref_sys carries NO organization_id column (no tenant data; INV-22 N/A)'
);

SELECT cmp_ok(
  (SELECT count(*) FROM public.spatial_ref_sys)::int,
  '>=', 8300,
  'spatial_ref_sys row count within expected EPSG bounds (TRUNCATE-tamper detector)'
);

SELECT * FROM finish();
ROLLBACK;
