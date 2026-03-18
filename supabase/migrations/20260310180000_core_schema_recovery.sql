-- ============================================================
-- PactaFlow Core Schema Recovery Migration
-- Target: Recover missing tables (drivers, routes, trips_audit)
-- ============================================================

-- 1. DRIVERS
CREATE TABLE IF NOT EXISTS public.drivers (
    id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    full_name TEXT NOT NULL,
    license_number TEXT UNIQUE NOT NULL,
    status TEXT DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'pending')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. ROUTES
CREATE TABLE IF NOT EXISTS public.routes (
    id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    gtfs_route_id TEXT UNIQUE,
    short_name TEXT,
    long_name TEXT DEFAULT '',
    color TEXT,
    agency_id TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. TRIPS AUDIT (The reality table expected by TripRepositoryImpl)
CREATE TABLE IF NOT EXISTS public.trips_audit (
    id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    driver_id UUID REFERENCES public.drivers(id) ON DELETE SET NULL,
    route_id UUID REFERENCES public.routes(id) ON DELETE CASCADE,
    status TEXT DEFAULT 'scheduled' 
        CHECK (status IN ('scheduled', 'active', 'completed', 'cancelled')),
    start_time TIMESTAMPTZ DEFAULT NOW(),
    end_time TIMESTAMPTZ,
    source_type TEXT DEFAULT 'manual',
    organization_id UUID, -- For multi-tenancy foundation compatibility
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. RLS & Security (QA & Security Lead Compliance)
ALTER TABLE public.drivers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.routes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trips_audit ENABLE ROW LEVEL SECURITY;

-- Basic Policies (Adjusted for multi-tenancy if organization_id exists)
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Tenant Access Drivers') THEN
        CREATE POLICY "Tenant Access Drivers" ON public.drivers
            FOR ALL USING (TRUE); -- Simple for now, refine based on org_id if added later
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Tenant Access Routes') THEN
        CREATE POLICY "Tenant Access Routes" ON public.routes
            FOR ALL USING (TRUE);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Tenant Access Trips') THEN
        CREATE POLICY "Tenant Access Trips" ON public.trips_audit
            FOR ALL USING (TRUE);
    END IF;
END $$;

-- 5. Replication (Realtime)
-- Note: Realtime must be enabled via Supabase dashboard or SQL:
-- ALTER PUBLICATION supabase_realtime ADD TABLE trips_audit;
