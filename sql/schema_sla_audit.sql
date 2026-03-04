-- ============================================================
-- BusFlow Operational Control Center — SLA Audit Schema
-- ============================================================
-- Extension of schema.sql for the SLA Audit Domain
-- Target: Supabase (PostgreSQL 15+)
-- ============================================================

-- ============================================================
-- 1. PLAN DECLARATIONS (Aggregate Root)
-- Source of truth for contractual operational plans. Immutability enforced by lack of UPDATE privileges.
-- ============================================================
CREATE TABLE public.plan_declarations (
    id UUID PRIMARY KEY,
    contract_id TEXT NOT NULL,
    declared_at_utc TIMESTAMPTZ NOT NULL,
    declared_by_user_id TEXT NOT NULL,
    plan_version INTEGER NOT NULL,
    original_file_hash TEXT NOT NULL,
    -- Ensure monotonicity/immutability: contract + version must be unique
    UNIQUE(contract_id, plan_version)
);

-- ============================================================
-- 2. CONTRACTUAL SERVICE EXECUTIONS (Child Entity)
-- Individual service execution obligations.
-- ============================================================
CREATE TABLE public.contractual_service_executions (
    set_id TEXT PRIMARY KEY,
    plan_declaration_id UUID NOT NULL REFERENCES public.plan_declarations(id) ON DELETE CASCADE,
    scheduled_start_time_utc TIMESTAMPTZ NOT NULL,
    scheduled_end_time_utc TIMESTAMPTZ NOT NULL,
    start_latitude DOUBLE PRECISION NOT NULL,
    start_longitude DOUBLE PRECISION NOT NULL,
    start_radius_meters INTEGER NOT NULL,
    end_latitude DOUBLE PRECISION NOT NULL,
    end_longitude DOUBLE PRECISION NOT NULL,
    end_radius_meters INTEGER NOT NULL,
    planned_vehicle_id TEXT, -- Nullable (can be any vehicle)
    contractual_value DOUBLE PRECISION NOT NULL CHECK (contractual_value > 0),
    no_show_penalty_multiplier DOUBLE PRECISION NOT NULL CHECK (no_show_penalty_multiplier >= 1.0)
);

CREATE INDEX idx_contractual_services_plan ON public.contractual_service_executions(plan_declaration_id);

-- ============================================================
-- 3. EXECUTION STATES (Aggregate Root)
-- Dynamic state tracking evaluation of service executions.
-- ============================================================
CREATE TABLE public.execution_states (
    id UUID PRIMARY KEY,
    set_id TEXT UNIQUE NOT NULL REFERENCES public.contractual_service_executions(set_id) ON DELETE CASCADE,
    contract_id TEXT NOT NULL,
    plan_version INTEGER NOT NULL,
    
    -- Denormalized for rapid evaluation queries
    start_latitude DOUBLE PRECISION NOT NULL,
    start_longitude DOUBLE PRECISION NOT NULL,
    start_radius_meters INTEGER NOT NULL,
    planned_vehicle_id TEXT,
    contractual_value DOUBLE PRECISION NOT NULL,
    no_show_penalty_multiplier DOUBLE PRECISION NOT NULL,
    
    window_start_utc TIMESTAMPTZ NOT NULL,
    window_end_utc TIMESTAMPTZ NOT NULL,
    
    status TEXT NOT NULL CHECK (status IN ('pending', 'executed', 'noShow', 'evidenceGap')),
    
    bound_vehicle_id TEXT,
    binding_timestamp_utc TIMESTAMPTZ,
    binding_latitude DOUBLE PRECISION,
    binding_longitude DOUBLE PRECISION,
    
    created_at_utc TIMESTAMPTZ NOT NULL,
    last_evaluated_at_utc TIMESTAMPTZ NOT NULL,
    status_last_updated_at_utc TIMESTAMPTZ NOT NULL,
    finalized_at_utc TIMESTAMPTZ
);

CREATE INDEX idx_execution_states_contract ON public.execution_states(contract_id, status);
CREATE INDEX idx_execution_states_window ON public.execution_states(window_start_utc, window_end_utc);
CREATE INDEX idx_execution_states_status ON public.execution_states(status);

-- ============================================================
-- 4. EXECUTION STATE TRANSITIONS (Action Log)
-- Append-only audit history of state machine transitions.
-- ============================================================
CREATE TABLE public.execution_state_transitions (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    execution_state_id UUID NOT NULL REFERENCES public.execution_states(id) ON DELETE CASCADE,
    previous_status TEXT,
    new_status TEXT NOT NULL,
    transitioned_at_utc TIMESTAMPTZ NOT NULL,
    reason TEXT NOT NULL,
    metadata JSONB
);

CREATE INDEX idx_execution_transitions_state_id ON public.execution_state_transitions(execution_state_id);

-- ============================================================
-- 5. SLA AUDIT LEDGER (Append-only forensic log)
-- ============================================================
CREATE TABLE public.sla_audit_ledger (
    -- Implicit monotonicity provided by postgres bigserial primary key 
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    type TEXT NOT NULL,
    set_id TEXT, -- Can be null for plan-level events
    contract_id TEXT NOT NULL,
    plan_version INTEGER NOT NULL,
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    occurred_at_utc TIMESTAMPTZ NOT NULL
);

CREATE INDEX idx_sla_audit_ledger_set_id ON public.sla_audit_ledger(set_id);
CREATE INDEX idx_sla_audit_ledger_contract ON public.sla_audit_ledger(contract_id);
CREATE INDEX idx_sla_audit_ledger_occurred ON public.sla_audit_ledger(occurred_at_utc);

-- ============================================================
-- 6. CONTRACTUAL FINANCIAL DAILY SNAPSHOT (Aggregate Root)
-- Daily financial closing representing exactly one day's data. Immutability enforced by lacking UPDATE privileges.
-- ============================================================
CREATE TABLE public.contractual_financial_snapshot (
    id UUID PRIMARY KEY,
    contract_id TEXT, -- Null represents global closure across all contracts
    operational_date_utc TIMESTAMPTZ NOT NULL,
    operational_timezone TEXT NOT NULL,
    closed_at_utc TIMESTAMPTZ NOT NULL,
    
    -- Values stored in cents to prevent floating point issues
    total_contracted_revenue_cents BIGINT NOT NULL,
    protected_revenue_cents BIGINT NOT NULL,
    revenue_at_risk_cents BIGINT NOT NULL,
    lost_revenue_cents BIGINT NOT NULL,
    
    risk_percentage DOUBLE PRECISION NOT NULL,
    loss_percentage DOUBLE PRECISION NOT NULL,
    
    last_ledger_entry_id BIGINT REFERENCES public.sla_audit_ledger(id) ON DELETE SET NULL,
    previous_snapshot_id UUID REFERENCES public.contractual_financial_snapshot(id) ON DELETE SET NULL, 
    reprocessing_reason TEXT,
    author_user_id TEXT
);

CREATE INDEX idx_financial_snapshot_date ON public.contractual_financial_snapshot(operational_date_utc);
CREATE INDEX idx_financial_snapshot_contract ON public.contractual_financial_snapshot(contract_id);

-- ============================================================
-- SECURITY HARDENING
-- ============================================================
-- Database-level invariants (REVOKE UPDATE/DELETE, RLS, policies)
-- are enforced by the migration:
--   supabase/migrations/20260304195300_sla_audit_hardening.sql
-- ============================================================
