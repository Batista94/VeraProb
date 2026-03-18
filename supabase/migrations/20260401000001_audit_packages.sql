-- =============================================================================
-- Phase 7.1 — Evidence & Audit Exports: Burden of Proof
-- Migration 1/3: audit_packages + shadow_mode_simulations tables
-- =============================================================================
-- EXECUTION ORDER: run this file once, top to bottom, in the Supabase SQL Editor.
-- Depends on: organizations, contracts tables (Phase 3/5).
-- =============================================================================

-- ---------------------------------------------------------------------------
-- TABLE: audit_packages
--
-- Immutable, sealed evidence aggregates for billing cycles.
-- D1-Canonical two-row strategy: draft row (packageHash IS NULL) and
-- sealed row (packageHash NOT NULL) are BOTH stored. The draft is never updated.
--
-- INV-1 (Immutable Ledger): UPDATE and DELETE are blocked by DB rules.
-- INV-6 (Multi-Tenant + RLS): organization_id on every record.
-- INV-16 (Export Sealing): packageHash computed server-side before export.
-- INV-17 (Attestation Mandate): attestation metadata (tenant_name, cnpjs) stored.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS audit_packages (
  id                        UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id           UUID        NOT NULL,
  contract_id               UUID        REFERENCES contracts(id),

  -- Denormalized contractor identity for export portability (no JOIN needed)
  contractor_name           TEXT        NOT NULL,

  -- Billing period
  period_start_utc          TIMESTAMPTZ NOT NULL,
  period_end_utc            TIMESTAMPTZ NOT NULL,

  -- Content provenance
  billing_cycle_report_id   TEXT        NOT NULL,  -- SHA-256 deterministic ID
  report_ledger_boundary    BIGINT      NOT NULL,  -- max(lastLedgerEntryId) across snapshots
  snapshot_ids              UUID[]      NOT NULL,  -- D2-Challenger: UUID[] array

  -- Financial summary (denormalized for export portability)
  total_contracted_revenue_cents  BIGINT NOT NULL DEFAULT 0,
  protected_revenue_cents         BIGINT NOT NULL DEFAULT 0,
  revenue_at_risk_cents           BIGINT NOT NULL DEFAULT 0,
  lost_revenue_cents              BIGINT NOT NULL DEFAULT 0,
  total_obligations               INT    NOT NULL DEFAULT 0,
  executed_count                  INT    NOT NULL DEFAULT 0,
  no_show_count                   INT    NOT NULL DEFAULT 0,
  evidence_gap_count              INT    NOT NULL DEFAULT 0,
  compliance_rate                 FLOAT  NOT NULL DEFAULT 0.0,

  -- Cryptographic seal (INV-16)
  package_hash              TEXT,       -- NULL until sealed. SHA-256 of canonical JSON.
  hash_algorithm            TEXT        NOT NULL DEFAULT 'SHA-256',

  -- Platform metadata
  schema_version            TEXT        NOT NULL DEFAULT '7.1.0',
  engine_version_at_gen     TEXT        NOT NULL,

  -- Lifecycle: draft → sealed → superseded
  status                    TEXT        NOT NULL DEFAULT 'draft'
                              CHECK (status IN ('draft', 'sealed', 'superseded')),

  -- Lineage chain (INV-1: superseded packages are never deleted)
  previous_package_id       UUID        REFERENCES audit_packages(id),
  supersession_reason       TEXT,

  -- Provenance
  generated_at_utc          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  generated_by_user_id      UUID        NOT NULL,

  -- Attestation header fields (INV-17 — denormalized for export independence)
  tenant_name               TEXT        NOT NULL,
  tenant_cnpj               TEXT,
  contractor_cnpj           TEXT,

  created_at                TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- Supersession invariant: if lineage exists, reason is mandatory
  CONSTRAINT supersession_reason_required
    CHECK (
      previous_package_id IS NULL OR
      (supersession_reason IS NOT NULL AND supersession_reason <> '')
    ),

  -- Period invariant
  CONSTRAINT period_valid
    CHECK (period_end_utc > period_start_utc),

  -- Ledger boundary non-negative
  CONSTRAINT ledger_boundary_non_negative
    CHECK (report_ledger_boundary >= 0)
);

-- ---------------------------------------------------------------------------
-- Immutability rules (INV-1)
-- Blocks UPDATE and DELETE at the DB layer, independently of application code.
-- ---------------------------------------------------------------------------
CREATE RULE audit_packages_no_update
  AS ON UPDATE TO audit_packages DO INSTEAD NOTHING;

CREATE RULE audit_packages_no_delete
  AS ON DELETE TO audit_packages DO INSTEAD NOTHING;

-- ---------------------------------------------------------------------------
-- Row Level Security (INV-6, INV-10)
-- Tenants see only their own packages. Uses JWT organization_id claim (INV-10).
-- ---------------------------------------------------------------------------
ALTER TABLE audit_packages ENABLE ROW LEVEL SECURITY;

CREATE POLICY "audit_packages_org_isolation"
  ON audit_packages
  FOR ALL
  USING (organization_id = (auth.jwt() ->> 'organization_id')::uuid);

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------
-- Primary query pattern: list sealed packages for an org, most recent first
CREATE INDEX idx_audit_packages_org_period
  ON audit_packages(organization_id, period_start_utc DESC);

-- Scoped to contract for single-contract billing cycles
CREATE INDEX idx_audit_packages_contract_period
  ON audit_packages(organization_id, contract_id, period_start_utc DESC);

-- Idempotency check: find active sealed package for org/contract/period
CREATE INDEX idx_audit_packages_active_sealed
  ON audit_packages(organization_id, contract_id, period_start_utc, period_end_utc, status)
  WHERE status = 'sealed';

-- Lineage traversal
CREATE INDEX idx_audit_packages_previous
  ON audit_packages(previous_package_id)
  WHERE previous_package_id IS NOT NULL;
