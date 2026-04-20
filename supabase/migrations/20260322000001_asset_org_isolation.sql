-- ============================================================
-- veraprob — Bloco 8: Asset Organization Isolation
-- Adds organization_id to drivers, routes, trips_audit
-- Replaces permissive USING (TRUE) policies with canonical
-- tenant isolation using (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid
-- ============================================================

-- Helper to drop all policies idempotently (local scope — dropped at end)
CREATE OR REPLACE FUNCTION drop_all_policies_for_table(target_table text)
RETURNS void AS $$
DECLARE
    pol record;
BEGIN
    FOR pol IN
        SELECT policyname
        FROM pg_policies
        WHERE schemaname = 'public' AND tablename = target_table
    LOOP
        EXECUTE format('DROP POLICY %I ON public.%I', pol.policyname, target_table);
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- ── 1. drivers ───────────────────────────────────────────────
-- organization_id already added in 20260310190000_fix_rls_recovery_tables.sql

-- Backfill dev data (assigns all orphaned rows to the first org found)
UPDATE public.drivers
SET organization_id = (SELECT id FROM public.organizations ORDER BY created_at LIMIT 1)
WHERE organization_id IS NULL;

ALTER TABLE public.drivers
    ALTER COLUMN organization_id SET NOT NULL;

ALTER TABLE public.drivers
    ADD CONSTRAINT fk_drivers_organization
    FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_drivers_organization_id
    ON public.drivers (organization_id);

-- Drop the global UNIQUE on license_number; license is unique per org
ALTER TABLE public.drivers DROP CONSTRAINT IF EXISTS drivers_license_number_key;

ALTER TABLE public.drivers
    ADD CONSTRAINT uq_drivers_org_license UNIQUE (organization_id, license_number);

SELECT drop_all_policies_for_table('drivers');
ALTER TABLE public.drivers ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Tenant Isolation: drivers" ON public.drivers
    FOR ALL USING (
        organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid
    )
    WITH CHECK (
        organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid
    );

-- ── 2. routes ────────────────────────────────────────────────
ALTER TABLE public.routes
    ADD COLUMN IF NOT EXISTS organization_id UUID;

UPDATE public.routes
SET organization_id = (SELECT id FROM public.organizations ORDER BY created_at LIMIT 1)
WHERE organization_id IS NULL;

ALTER TABLE public.routes
    ALTER COLUMN organization_id SET NOT NULL;

ALTER TABLE public.routes
    ADD CONSTRAINT fk_routes_organization
    FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_routes_organization_id
    ON public.routes (organization_id);

-- Replace global gtfs_route_id uniqueness with per-tenant uniqueness
-- (two tenants can import the same GTFS route independently)
ALTER TABLE public.routes DROP CONSTRAINT IF EXISTS routes_gtfs_route_id_key;

ALTER TABLE public.routes
    ADD CONSTRAINT uq_routes_org_gtfs_id UNIQUE (organization_id, gtfs_route_id);

SELECT drop_all_policies_for_table('routes');
ALTER TABLE public.routes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Tenant Isolation: routes" ON public.routes
    FOR ALL USING (
        organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid
    )
    WITH CHECK (
        organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid
    );

-- ── 3. trips_audit: harden existing organization_id ─────────
-- Column exists but is nullable and has no FK — fix both

ALTER TABLE public.trips_audit
    ADD CONSTRAINT fk_trips_organization
    FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;

UPDATE public.trips_audit
SET organization_id = (SELECT id FROM public.organizations ORDER BY created_at LIMIT 1)
WHERE organization_id IS NULL;

ALTER TABLE public.trips_audit
    ALTER COLUMN organization_id SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_trips_audit_organization_id
    ON public.trips_audit (organization_id);

SELECT drop_all_policies_for_table('trips_audit');
ALTER TABLE public.trips_audit ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Tenant Isolation: trips_audit" ON public.trips_audit
    FOR ALL USING (
        organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid
    )
    WITH CHECK (
        organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid
    );

-- Cleanup
DROP FUNCTION drop_all_policies_for_table(text);
