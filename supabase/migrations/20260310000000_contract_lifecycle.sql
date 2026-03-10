-- ============================================================
-- BusFlow — Phase 5: Contract & Plan Lifecycle Management
-- ============================================================
-- REASON:
--   The evaluation engine (Phases 0–4) operates over a `contractId`
--   string with no backing entity. Phase 5 introduces the `Contract`
--   aggregate as the formal anchor for plan declarations, enabling
--   lifecycle management (draft → active → closed) and referential
--   integrity at the DB level.
--
-- STRATEGY:
--   1. Create `contracts` table with status check constraint and RLS
--   2. Add `contract_fk` FK column to `plan_declarations`
--   3. Create performance indexes
--
-- NOTE (CR-4):
--   Dev bank reset is executed before applying this migration.
--   No backfill is required — no production data to preserve.
-- ============================================================

-- ── 1. contracts table ─────────────────────────────────────

CREATE TABLE public.contracts (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id     UUID NOT NULL REFERENCES public.organizations(id),
  name                TEXT NOT NULL,
  contractor_name     TEXT NOT NULL,
  description         TEXT,
  valid_from_utc      TIMESTAMPTZ NOT NULL,
  valid_until_utc     TIMESTAMPTZ NOT NULL,
  status              TEXT NOT NULL DEFAULT 'draft'
                      CHECK (status IN ('draft', 'active', 'closed')),
  created_at_utc      TIMESTAMPTZ NOT NULL DEFAULT now(),
  activated_at_utc    TIMESTAMPTZ,
  closed_at_utc       TIMESTAMPTZ,
  closed_by_user_id   TEXT,
  close_reason        TEXT,
  CONSTRAINT valid_period CHECK (valid_until_utc > valid_from_utc)
);

-- Indexes for frequent query patterns
CREATE INDEX idx_contracts_org_status
  ON public.contracts (organization_id, status);

CREATE INDEX idx_contracts_org_created
  ON public.contracts (organization_id, created_at_utc DESC);

-- ── 2. Row Level Security ───────────────────────────────────

ALTER TABLE public.contracts ENABLE ROW LEVEL SECURITY;

-- Operators only see and write contracts belonging to their own organization.
-- organization_id is derived from the authenticated JWT — never from user input.
CREATE POLICY "Contract tenant isolation"
  ON public.contracts FOR ALL TO authenticated
  USING (organization_id = (auth.jwt() ->> 'organization_id')::UUID)
  WITH CHECK (organization_id = (auth.jwt() ->> 'organization_id')::UUID);

-- ── 3. FK in plan_declarations ─────────────────────────────

-- Add a typed UUID FK alongside the existing TEXT `contract_id`.
-- The TEXT column is preserved for compatibility with the domain model
-- (aggregates reference each other by ID as String in Dart).
-- Phase 8 will consolidate these two columns.
ALTER TABLE public.plan_declarations
  ADD COLUMN contract_fk UUID REFERENCES public.contracts(id);

-- Index to support JOIN queries (ContractQueryService detail view)
CREATE INDEX idx_plan_declarations_contract_fk
  ON public.plan_declarations (contract_fk);
