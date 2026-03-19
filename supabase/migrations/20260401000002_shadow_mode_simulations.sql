-- =============================================================================
-- Phase 7.1 — Evidence & Audit Exports: Burden of Proof
-- Migration 2/3: shadow_mode_simulations table
-- =============================================================================
-- EXECUTION ORDER: run after 20260401000001_audit_packages.sql.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- TABLE: shadow_mode_simulations
--
-- Stores historical ROI simulations answering:
-- "What financial losses would have occurred without veraprob enforcement?"
--
-- Used by the Executive Dashboard and Contractor Portal to demonstrate
-- the platform's financial protection value (Sales tool + B2B proof point).
--
-- INV-1: Append-only (UPDATE/DELETE blocked by DB rules).
-- INV-2: All monetary values stored as BIGINT cents.
-- INV-6: organization_id on every record, RLS enforced.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS shadow_mode_simulations (
  id                                    UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id                       UUID        NOT NULL,
  simulation_name                       TEXT        NOT NULL,

  -- Period
  period_start_utc                      TIMESTAMPTZ NOT NULL,
  period_end_utc                        TIMESTAMPTZ NOT NULL,

  -- Actual platform data
  actual_protected_revenue_cents        BIGINT      NOT NULL,
  actual_lost_revenue_cents             BIGINT      NOT NULL,
  actual_at_risk_revenue_cents          BIGINT      NOT NULL,
  actual_compliance_rate                FLOAT       NOT NULL,

  -- Evidence quality (computed from canonical_facts integrity flags)
  -- Low values indicate contractor hardware quality issues (NOT veraprob failures).
  evidence_quality_rate                 FLOAT       NOT NULL DEFAULT 100.0,

  -- Simulation parameters
  baseline_dispute_rate                 FLOAT       NOT NULL,  -- % of penalties that would be disputed
  manual_enforcement_cost_per_incident_cents BIGINT NOT NULL,  -- labor cost per incident
  incident_count                        INT         NOT NULL,

  -- Computed ROI
  simulated_lost_revenue_cents          BIGINT      NOT NULL,  -- actualLost × (1 − disputeRate/100)
  revenue_protected_by_platform_cents   BIGINT      NOT NULL,  -- (actualLost − simulated) + labor savings
  roi_percentage                        FLOAT       NOT NULL,  -- (protected / subscription) × 100

  -- Simulation parameters as JSONB for full audit trail
  simulation_parameters                 JSONB       NOT NULL DEFAULT '{}',

  -- Provenance
  generated_at_utc                      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  generated_by_user_id                  UUID        NOT NULL,

  created_at                            TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- Invariants
  CONSTRAINT period_valid
    CHECK (period_end_utc > period_start_utc),

  CONSTRAINT evidence_quality_range
    CHECK (evidence_quality_rate >= 0.0 AND evidence_quality_rate <= 100.0),

  CONSTRAINT baseline_dispute_range
    CHECK (baseline_dispute_rate >= 0.0 AND baseline_dispute_rate <= 100.0)
);

-- ---------------------------------------------------------------------------
-- Immutability rules (INV-1)
-- ---------------------------------------------------------------------------
CREATE RULE shadow_mode_simulations_no_update
  AS ON UPDATE TO shadow_mode_simulations DO INSTEAD NOTHING;

CREATE RULE shadow_mode_simulations_no_delete
  AS ON DELETE TO shadow_mode_simulations DO INSTEAD NOTHING;

-- ---------------------------------------------------------------------------
-- Row Level Security (INV-6, INV-10)
-- ---------------------------------------------------------------------------
ALTER TABLE shadow_mode_simulations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "shadow_mode_simulations_org_isolation"
  ON shadow_mode_simulations
  FOR ALL
  USING (organization_id = (auth.jwt() ->> 'organization_id')::uuid);

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------
-- Primary query pattern: list simulations for org, most recent first
CREATE INDEX idx_shadow_mode_simulations_org_date
  ON shadow_mode_simulations(organization_id, generated_at_utc DESC);
