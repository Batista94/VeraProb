-- pr_scanner: ignore-rls (policies superseded by 20260317000001_rls_jwt_path_unification.sql)
-- =====================================================================
-- MULTI-TENANCY & AUTHENTICATION FOUNDATION MIGRATION
-- Purpose: Introduce strict organizational boundaries and RLS isolation.
-- Applies: HASH Partitioning, Composite Keys, and Auth Injection
-- =====================================================================

-- 1. Create the Core Multi-Tenancy Tables
CREATE TABLE organizations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

-- Extend auth.users with RBAC and Tenant links
CREATE TABLE user_roles (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    role VARCHAR(50) NOT NULL CHECK (role IN ('TENANT_ADMIN', 'OPERATOR', 'AUDITOR')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =====================================================================
-- 2. Modify Ledger to enforce organization_id and HASH Partitioning
-- Note: PostgreSQL requires partitioning to be defined at creation.
-- In a real scenario, this involves data migration. For this schema,
-- we define the target end-state architecture.
-- =====================================================================

CREATE TABLE sla_audit_ledger_v2 (
    id UUID NOT NULL DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id),
    timestamp TIMESTAMPTZ NOT NULL,
    action_type VARCHAR(255) NOT NULL,
    entity_id VARCHAR(255) NOT NULL,
    operator_id VARCHAR(255) NOT NULL,
    old_value TEXT,
    new_value TEXT,
    reason TEXT,
    payload JSONB,
    PRIMARY KEY (organization_id, id) -- Composite key for partition routing
) PARTITION BY HASH (organization_id);

-- Create HASH partitions (example with 4 partitions for local dev/MVP scale, production typically 64)
CREATE TABLE sla_audit_ledger_p0 PARTITION OF sla_audit_ledger_v2 FOR VALUES WITH (MODULUS 4, REMAINDER 0);
CREATE TABLE sla_audit_ledger_p1 PARTITION OF sla_audit_ledger_v2 FOR VALUES WITH (MODULUS 4, REMAINDER 1);
CREATE TABLE sla_audit_ledger_p2 PARTITION OF sla_audit_ledger_v2 FOR VALUES WITH (MODULUS 4, REMAINDER 2);
CREATE TABLE sla_audit_ledger_p3 PARTITION OF sla_audit_ledger_v2 FOR VALUES WITH (MODULUS 4, REMAINDER 3);

-- Create performance indexes within the partitions
CREATE INDEX idx_sla_ledger_org_time ON sla_audit_ledger_v2 (organization_id, timestamp DESC);
CREATE INDEX idx_sla_ledger_org_entity ON sla_audit_ledger_v2 (organization_id, entity_id);

-- =====================================================================
-- 3. Modify Projections for Composite Keys
-- =====================================================================

CREATE TABLE contractual_financial_snapshot_v2 (
    organization_id UUID NOT NULL REFERENCES organizations(id),
    trip_id VARCHAR(255) NOT NULL,
    total_fines_cents BIGINT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (organization_id, trip_id) -- Tenant-Safe Projection Key
);

-- =====================================================================
-- 4. Supabase JWT Claim Injection Hook
-- Automatically injects organization_id and role into the JWT on login.
-- =====================================================================
CREATE OR REPLACE FUNCTION public.custom_access_token_hook(event jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
  DECLARE
    claims jsonb;
    user_role public.user_roles;
  BEGIN
    -- Fetch the user's role and organization
    SELECT * INTO user_role FROM public.user_roles WHERE user_id = (event->>'user_id')::uuid;

    claims := event->'claims';

    IF FOUND THEN
      -- Inject the required isolation context into the JWT
      claims := jsonb_set(claims, '{app_metadata, org_id}', to_jsonb(user_role.organization_id));
      claims := jsonb_set(claims, '{app_metadata, role}', to_jsonb(user_role.role));
    ELSE
      claims := jsonb_set(claims, '{app_metadata, org_id}', 'null');
      claims := jsonb_set(claims, '{app_metadata, role}', 'null');
    END IF;

    -- Update the event
    event := jsonb_set(event, '{claims}', claims);
    RETURN event;
  END;
$$;

-- Grant permissions for Supabase Auth to execute the hook
GRANT USAGE ON SCHEMA public TO supabase_auth_admin;
GRANT EXECUTE ON FUNCTION public.custom_access_token_hook TO supabase_auth_admin;

-- =====================================================================
-- 5. Strict Row-Level Security (RLS) Policies
-- =====================================================================

ALTER TABLE organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE sla_audit_ledger_v2 ENABLE ROW LEVEL SECURITY;
ALTER TABLE contractual_financial_snapshot_v2 ENABLE ROW LEVEL SECURITY;

-- Block EVERYTHING by default (Whitelist approach)
-- Note: 'request.jwt.claims' represents the authenticated user's JWT.

-- ORGANIZATIONS: Users can only see their own organization
CREATE POLICY "Tenant Isolation: Read Organization" ON organizations
FOR SELECT USING (
    id = (current_setting('request.jwt.claims', true)::json->'app_metadata'->>'org_id')::uuid
);

-- LEDGER: Users can only Read/Insert events targeting their own organization_id
CREATE POLICY "Tenant Isolation: Read Ledger" ON sla_audit_ledger_v2
FOR SELECT USING (
    organization_id = (current_setting('request.jwt.claims', true)::json->'app_metadata'->>'org_id')::uuid
);

CREATE POLICY "Tenant Isolation: Insert Ledger" ON sla_audit_ledger_v2
FOR INSERT WITH CHECK (
    organization_id = (current_setting('request.jwt.claims', true)::json->'app_metadata'->>'org_id')::uuid
);

-- FINANCIAL PROJECTIONS: Strict Tenant Isolation
CREATE POLICY "Tenant Isolation: Read Projections" ON contractual_financial_snapshot_v2
FOR SELECT USING (
    organization_id = (current_setting('request.jwt.claims', true)::json->'app_metadata'->>'org_id')::uuid
);

-- =====================================================================
-- 6. Engine Validation Trigger (Failsafe)
-- Prevent inserts where the application layer forgets the organization_id
-- =====================================================================
CREATE OR REPLACE FUNCTION strict_tenant_envelope_validation()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.organization_id IS NULL THEN
        RAISE EXCEPTION 'FATAL: Event rejected by Evaluation Engine. Missing organization_id context in envelope.';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER enforce_tenant_envelope_ledger
BEFORE INSERT ON sla_audit_ledger_v2
FOR EACH ROW EXECUTE FUNCTION strict_tenant_envelope_validation();
