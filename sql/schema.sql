-- ============================================================
-- PactaFlow Operational Control Center — Database Schema v2
-- ============================================================
-- Requires: PostGIS extension
-- Target: Supabase (PostgreSQL 15+ with PostGIS)
-- ============================================================

-- Enable extensions
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================
-- 1. DRIVERS
-- ============================================================
CREATE TABLE public.drivers (
    id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    full_name TEXT NOT NULL,
    license_number TEXT UNIQUE NOT NULL,
    status TEXT DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'pending')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 2. VEHICLES
-- ============================================================
CREATE TABLE public.vehicles (
    id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    plate TEXT UNIQUE NOT NULL,
    model TEXT,
    capacity INTEGER NOT NULL,
    status TEXT DEFAULT 'available'
        CHECK (status IN ('available', 'in_service', 'maintenance', 'retired')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 3. ROUTES (normalized from GTFS or manual)
-- ============================================================
CREATE TABLE public.routes (
    id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    gtfs_route_id TEXT UNIQUE,
    short_name TEXT NOT NULL,         -- e.g. "809U-10"
    long_name TEXT NOT NULL DEFAULT '',-- e.g. "Cidade Universitária"
    color TEXT,                        -- Hex color from GTFS
    agency_id TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 4. STOPS (transit stops from GTFS)
-- ============================================================
CREATE TABLE public.stops (
    id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    gtfs_stop_id TEXT UNIQUE,
    name TEXT NOT NULL,
    location GEOGRAPHY(POINT, 4326) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_stops_location ON public.stops USING GIST (location);

-- ============================================================
-- 5. ROUTE SHAPES (polyline geometry for map rendering)
-- ============================================================
CREATE TABLE public.route_shapes (
    id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    route_id UUID REFERENCES public.routes(id) ON DELETE CASCADE,
    gtfs_shape_id TEXT,
    geometry GEOGRAPHY(LINESTRING, 4326),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_route_shapes_route ON public.route_shapes(route_id);

-- ============================================================
-- 6. STOP SEQUENCES (order of stops per route)
-- ============================================================
CREATE TABLE public.stop_sequences (
    id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    route_id UUID REFERENCES public.routes(id) ON DELETE CASCADE,
    stop_id UUID REFERENCES public.stops(id) ON DELETE CASCADE,
    sequence_order INTEGER NOT NULL,
    UNIQUE(route_id, stop_id, sequence_order)
);

-- ============================================================
-- 7. SCHEDULED TRIPS (from GTFS Static — the plan)
-- ============================================================
CREATE TABLE public.scheduled_trips (
    id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    route_id UUID REFERENCES public.routes(id) ON DELETE CASCADE,
    gtfs_trip_id TEXT UNIQUE,
    headsign TEXT,
    direction_id INTEGER,             -- 0 or 1
    scheduled_start TIME NOT NULL,
    scheduled_end TIME,
    service_days TEXT[] DEFAULT '{}'::TEXT[], -- e.g. {'monday','tuesday',...}
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 8. OPERATIONAL TRIPS (the central entity — reality)
-- ============================================================
CREATE TABLE public.operational_trips (
    id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    scheduled_trip_id UUID REFERENCES public.scheduled_trips(id) ON DELETE SET NULL,
    driver_id UUID REFERENCES public.drivers(id) ON DELETE SET NULL,
    vehicle_id UUID REFERENCES public.vehicles(id) ON DELETE SET NULL,
    route_id UUID NOT NULL REFERENCES public.routes(id) ON DELETE CASCADE,
    status TEXT DEFAULT 'scheduled'
        CHECK (status IN (
            'scheduled', 'dispatched', 'en_route', 'at_stop',
            'delayed', 'interrupted', 'completed', 'cancelled', 'no_show'
        )),
    scheduled_start TIMESTAMPTZ NOT NULL,
    scheduled_end TIMESTAMPTZ,
    actual_start TIMESTAMPTZ,
    actual_end TIMESTAMPTZ,
    delay_seconds INTEGER DEFAULT 0,
    completion_pct DOUBLE PRECISION DEFAULT 0.0,
    source_type TEXT DEFAULT 'manual'
        CHECK (source_type IN ('manual', 'gtfs_static', 'gtfs_realtime')),
    external_trip_id TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_operational_trips_status ON public.operational_trips(status);
CREATE INDEX idx_operational_trips_route ON public.operational_trips(route_id);
CREATE INDEX idx_operational_trips_driver ON public.operational_trips(driver_id);
CREATE INDEX idx_operational_trips_date ON public.operational_trips(scheduled_start);

-- ============================================================
-- 9. TRIP EVENTS (immutable audit log)
-- ============================================================
CREATE TABLE public.trip_events (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    trip_id UUID NOT NULL REFERENCES public.operational_trips(id) ON DELETE CASCADE,
    event_type TEXT NOT NULL
        CHECK (event_type IN (
            'status_change', 'delay_detected', 'delay_recovered',
            'position_lost', 'position_restored',
            'driver_assigned', 'vehicle_assigned',
            'feed_disconnected', 'feed_reconnected',
            'manual_override'
        )),
    from_status TEXT,
    to_status TEXT,
    metadata JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_trip_events_trip ON public.trip_events(trip_id);
CREATE INDEX idx_trip_events_type ON public.trip_events(event_type);
CREATE INDEX idx_trip_events_time ON public.trip_events(created_at);

-- ============================================================
-- 10. VEHICLE POSITIONS (realtime GPS tracking)
-- ============================================================
CREATE TABLE public.vehicle_positions (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    trip_id UUID REFERENCES public.operational_trips(id) ON DELETE CASCADE,
    location GEOGRAPHY(POINT, 4326) NOT NULL,
    speed DOUBLE PRECISION,
    heading DOUBLE PRECISION,
    source TEXT NOT NULL CHECK (source IN ('api_public', 'driver_app_gps')),
    timestamp TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_vehicle_positions_location ON public.vehicle_positions USING GIST (location);
CREATE INDEX idx_vehicle_positions_trip ON public.vehicle_positions(trip_id);
CREATE INDEX idx_vehicle_positions_time ON public.vehicle_positions(timestamp);

-- ============================================================
-- ROW LEVEL SECURITY (basic setup)
-- ============================================================
ALTER TABLE public.drivers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vehicles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.routes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stops ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.operational_trips ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trip_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vehicle_positions ENABLE ROW LEVEL SECURITY;

-- Public read access (for MVP — restrict in production)
CREATE POLICY "Public Read" ON public.drivers FOR SELECT USING (true);
CREATE POLICY "Public Read" ON public.vehicles FOR SELECT USING (true);
CREATE POLICY "Public Read" ON public.routes FOR SELECT USING (true);
CREATE POLICY "Public Read" ON public.stops FOR SELECT USING (true);
CREATE POLICY "Public Read" ON public.operational_trips FOR SELECT USING (true);
CREATE POLICY "Public Read" ON public.trip_events FOR SELECT USING (true);
CREATE POLICY "Public Read" ON public.vehicle_positions FOR SELECT USING (true);

-- Authenticated write access
CREATE POLICY "Auth Insert" ON public.vehicle_positions
    FOR INSERT WITH CHECK (auth.role() = 'authenticated');
CREATE POLICY "Auth Insert" ON public.trip_events
    FOR INSERT WITH CHECK (auth.role() = 'authenticated');
CREATE POLICY "Auth All" ON public.operational_trips
    FOR ALL USING (auth.role() = 'authenticated');
CREATE POLICY "Auth All" ON public.drivers
    FOR ALL USING (auth.role() = 'authenticated');
CREATE POLICY "Auth All" ON public.vehicles
    FOR ALL USING (auth.role() = 'authenticated');

-- ============================================================
-- REALTIME SUBSCRIPTION (enable for key tables)
-- ============================================================
-- Run in Supabase Dashboard > Database > Replication:
-- Enable realtime for: operational_trips, vehicle_positions, trip_events
