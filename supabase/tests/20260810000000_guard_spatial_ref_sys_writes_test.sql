CREATE OR REPLACE FUNCTION run_spatial_guard_tests()
RETURNS SETOF text LANGUAGE plpgsql AS $$
BEGIN
  IF to_regclass('public.spatial_ref_sys') IS NOT NULL THEN
    RETURN NEXT plan(7);
    RETURN NEXT has_function('public', 'guard_spatial_ref_sys_writes', ARRAY[]::text[]);
    RETURN NEXT ok(
      EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgrelid = to_regclass('public.spatial_ref_sys')
          AND tgname  = 'guard_spatial_ref_sys_writes_trg'
          AND NOT tgisinternal
      ),
      'guard trigger is attached to public.spatial_ref_sys'
    );
    RETURN NEXT throws_ok(
      'DELETE FROM public.spatial_ref_sys WHERE srid = -99999',
      '42501',
      'anon DELETE on spatial_ref_sys is blocked by the guard'
    );
    RETURN NEXT throws_ok(
      'UPDATE public.spatial_ref_sys SET auth_name = auth_name WHERE srid = -99999',
      '42501',
      'authenticated UPDATE on spatial_ref_sys is blocked by the guard'
    );
    RETURN NEXT lives_ok(
      'DELETE FROM public.spatial_ref_sys WHERE srid = -99999',
      'privileged role (postgres) is NOT blocked by the guard (0-row no-op)'
    );
    RETURN NEXT ok(
      NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name   = 'spatial_ref_sys'
          AND column_name  = 'organization_id'
      ),
      'spatial_ref_sys carries NO organization_id column (no tenant data; INV-22 N/A)'
    );
    RETURN NEXT cmp_ok(
      (SELECT count(*) FROM public.spatial_ref_sys)::int,
      '>=', 8300,
      'spatial_ref_sys row count within expected EPSG bounds (TRUNCATE-tamper detector)'
    );
  ELSE
    RETURN NEXT plan(1);
    RETURN NEXT ok(
      to_regclass('public.spatial_ref_sys') IS NULL,
      'spatial_ref_sys has been relocated out of the public schema (definitive fix applied)'
    );
  END IF;
END;
$$;

SELECT run_spatial_guard_tests();
DROP FUNCTION run_spatial_guard_tests();

SELECT * FROM finish();
ROLLBACK;
