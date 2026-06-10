-- =============================================================================
-- Migration: Write-guard for public.spatial_ref_sys (INTERIM compensating control)
--
-- Advisory: `rls_disabled_in_public` on public.spatial_ref_sys (PostGIS catalog).
--
-- PROBLEM: spatial_ref_sys is owned by `supabase_admin` (PostGIS extension catalog).
-- The `postgres` migration role is non-owner/non-superuser/non-grantor, so it CANNOT:
--   - ENABLE ROW LEVEL SECURITY (owner-only),
--   - REVOKE the INSERT/UPDATE/DELETE/TRUNCATE grants held by anon/authenticated
--     (grantor-only — the REVOKE in 20260602000001 silently no-op'd in production;
--      20260527000001 and 20260804000001 correctly shipped no statement and only
--      documented the impossibility; see the accept-risk record).
-- Result: an extracted anon key can DELETE/TRUNCATE the SRID catalog via the Data
-- API, degrading the GPS spatial RPCs (autonomous closer / auto-start). This is a
-- MEDIUM Integrity/Availability vector (no tenant data => no INV-1/INV-22 breach).
--
-- WHAT WE CAN DO AT THE postgres TIER: `postgres` holds the TRIGGER privilege on the
-- table (verified). A BEFORE statement-level trigger that RAISEs blocks the mutation
-- before any damage — closing the vector WITHOUT supabase_admin.
--
-- ROLE-SCOPED so platform maintenance is never blocked:
--   - anon / authenticated      -> BLOCKED (no legitimate reason to write a SRID catalog)
--   - supabase_admin / postgres / service_role / any other role -> ALLOWED
--     (PostGIS install/upgrade runs as supabase_admin via populate_spatial_ref_sys()).
-- The application never writes this table (reference data only), so blocking client
-- roles has zero functional impact.
--
-- LIFECYCLE: This is the INTERIM control. The ROOT-CAUSE fix is relocating PostGIS to
-- the `extensions` schema (20260810000001 + Supabase support ticket). When
-- supabase_admin runs `DROP EXTENSION postgis CASCADE`, public.spatial_ref_sys is
-- dropped and this trigger is removed automatically (DDL DROP does not fire DML
-- triggers) — no cleanup migration required.
--
-- Invariants: INV-2 (defense-in-depth on a public-schema table), INV-22 (attack
-- surface reduction). INV-DB: no destructive DDL.
-- =============================================================================

SET client_min_messages TO 'WARNING';

CREATE OR REPLACE FUNCTION public.guard_spatial_ref_sys_writes()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  -- Allow privileged/maintenance roles (PostGIS upgrades run as supabase_admin).
  IF current_user IN ('anon', 'authenticated') THEN
    RAISE EXCEPTION
      'spatial_ref_sys is a read-only PostGIS reference catalog: % denied for role %',
      TG_OP, current_user
      USING ERRCODE = '42501'; -- insufficient_privilege
  END IF;
  RETURN NULL; -- statement-level trigger ignores the return value
END;
$$;

COMMENT ON FUNCTION public.guard_spatial_ref_sys_writes IS
  'INTERIM compensating control: blocks INSERT/UPDATE/DELETE/TRUNCATE on spatial_ref_sys by anon/authenticated (Data API) while PostGIS lives in public. Removed when PostGIS relocates to extensions. INV-2, INV-22.'; -- INV-DB: zero-downtime-verified (COMMENT text, not DML; Council-approved 20260810000002)

DROP TRIGGER IF EXISTS guard_spatial_ref_sys_writes_trg ON public.spatial_ref_sys;
CREATE TRIGGER guard_spatial_ref_sys_writes_trg
  BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON public.spatial_ref_sys -- INV-DB: zero-downtime-verified (trigger event clause, not DML; Council-approved 20260810000002)
  FOR EACH STATEMENT
  EXECUTE FUNCTION public.guard_spatial_ref_sys_writes();
