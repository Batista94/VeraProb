-- Migration: Fix drivers and trips_audit RLS JWT path
-- Root cause: Migration 20260310190000_fix_rls_recovery_tables used the wrong JWT path.
-- The custom_access_token_hook injects org_id under app_metadata.

-- 1. DRIVERS
DROP POLICY IF EXISTS "Drivers: tenant read" ON public.drivers;
DROP POLICY IF EXISTS "Drivers: tenant insert" ON public.drivers;
DROP POLICY IF EXISTS "Drivers: tenant update" ON public.drivers;

CREATE POLICY "Drivers: tenant read" ON public.drivers
    FOR SELECT
    USING (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid);

CREATE POLICY "Drivers: tenant insert" ON public.drivers
    FOR INSERT
    WITH CHECK (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid);

CREATE POLICY "Drivers: tenant update" ON public.drivers
    FOR UPDATE
    USING (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid)
    WITH CHECK (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid);

-- 2. TRIPS AUDIT
DROP POLICY IF EXISTS "Trips: tenant read" ON public.trips_audit;
DROP POLICY IF EXISTS "Trips: tenant insert" ON public.trips_audit;
DROP POLICY IF EXISTS "Trips: tenant update" ON public.trips_audit;

CREATE POLICY "Trips: tenant read" ON public.trips_audit
    FOR SELECT
    USING (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid);

CREATE POLICY "Trips: tenant insert" ON public.trips_audit
    FOR INSERT
    WITH CHECK (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid);

CREATE POLICY "Trips: tenant update" ON public.trips_audit
    FOR UPDATE
    USING (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid)
    WITH CHECK (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid);
