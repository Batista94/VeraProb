-- ============================================================
-- PactaFlow — Bloco 8: Vehicles Asset Table
-- Creates the vehicles table with full multi-tenant isolation.
-- Note: This is the ASSET table for fleet management CRUD.
-- It is distinct from telemetry/position tracking.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.vehicles (
    id              UUID        PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    organization_id UUID        NOT NULL,
    plate           TEXT        NOT NULL,
    model           TEXT,
    capacity        INT         NOT NULL DEFAULT 0 CHECK (capacity >= 0),
    status          TEXT        NOT NULL DEFAULT 'available'
                                CHECK (status IN ('available', 'in_service', 'maintenance', 'retired')),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Plate is unique per tenant; different orgs can have identical plates
    CONSTRAINT uq_vehicles_org_plate     UNIQUE (organization_id, plate),
    CONSTRAINT fk_vehicles_organization  FOREIGN KEY (organization_id)
        REFERENCES public.organizations(id) ON DELETE CASCADE
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_vehicles_organization_id
    ON public.vehicles (organization_id);

CREATE INDEX IF NOT EXISTS idx_vehicles_org_status
    ON public.vehicles (organization_id, status);

-- RLS
ALTER TABLE public.vehicles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Tenant Isolation: vehicles" ON public.vehicles
    FOR ALL USING (
        organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid
    )
    WITH CHECK (
        organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid
    );

-- Auto-update updated_at on mutation
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_vehicles_updated_at
    BEFORE UPDATE ON public.vehicles
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
