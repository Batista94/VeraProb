-- ============================================================
-- BusFlow RLS Patch: Recovery Tables Security Fix
-- Addresses: USING (TRUE) policies on multi-tenant tables
-- Council Decision: 2026-03-10
-- ============================================================

-- ─── 1. DRIVERS — Add organization_id + tenant isolation ───

ALTER TABLE public.drivers
    ADD COLUMN IF NOT EXISTS organization_id UUID;

DROP POLICY IF EXISTS "Tenant Access Drivers" ON public.drivers;

CREATE POLICY "Drivers: tenant read" ON public.drivers
    FOR SELECT
    USING (organization_id = (auth.jwt() ->> 'org_id')::uuid);

CREATE POLICY "Drivers: tenant insert" ON public.drivers
    FOR INSERT
    WITH CHECK (organization_id = (auth.jwt() ->> 'org_id')::uuid);

CREATE POLICY "Drivers: tenant update" ON public.drivers
    FOR UPDATE
    USING (organization_id = (auth.jwt() ->> 'org_id')::uuid)
    WITH CHECK (organization_id = (auth.jwt() ->> 'org_id')::uuid);

-- DELETE is intentionally omitted: drivers are soft-deactivated via status field.

-- ─── 2. ROUTES — Public read (GTFS shared infra), no tenant write ───
-- Routes follow GTFS semantics: global shared reference data.
-- Tenants may read all routes but cannot insert/update/delete them.
-- Ownership model will be refined in Phase 8 if private routes are needed.

DROP POLICY IF EXISTS "Tenant Access Routes" ON public.routes;

CREATE POLICY "Routes: public read" ON public.routes
    FOR SELECT
    USING (TRUE);

-- No INSERT/UPDATE/DELETE policy for tenant users: routes are managed
-- by system-level migrations or admin service accounts, not tenant sessions.

-- ─── 3. TRIPS AUDIT — Fix ignored organization_id ───

DROP POLICY IF EXISTS "Tenant Access Trips" ON public.trips_audit;

CREATE POLICY "Trips: tenant read" ON public.trips_audit
    FOR SELECT
    USING (organization_id = (auth.jwt() ->> 'org_id')::uuid);

CREATE POLICY "Trips: tenant insert" ON public.trips_audit
    FOR INSERT
    WITH CHECK (organization_id = (auth.jwt() ->> 'org_id')::uuid);

CREATE POLICY "Trips: tenant update" ON public.trips_audit
    FOR UPDATE
    USING (organization_id = (auth.jwt() ->> 'org_id')::uuid)
    WITH CHECK (organization_id = (auth.jwt() ->> 'org_id')::uuid);
