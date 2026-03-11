-- Migration: Schema sync — align DB columns with Dart domain model
-- Root cause: sql/schema_sla_audit.sql base and incremental migrations diverged
-- from Dart infrastructure layer evolution across phases.
-- NOTE: Block 2 (contractual_evaluation_traces rename) was omitted —
--       the column 'decisions' already existed with the correct name.

-- ── Block 1: sla_audit_ledger_v2 ─────────────────────────────────────────────
ALTER TABLE public.sla_audit_ledger_v2 RENAME COLUMN "timestamp" TO occurred_at_utc;
ALTER TABLE public.sla_audit_ledger_v2 RENAME COLUMN action_type TO type;
ALTER TABLE public.sla_audit_ledger_v2 RENAME COLUMN entity_id TO set_id;
ALTER TABLE public.sla_audit_ledger_v2 ALTER COLUMN operator_id DROP NOT NULL;
ALTER TABLE public.sla_audit_ledger_v2 ADD COLUMN IF NOT EXISTS plan_version INT;

-- ── Block 3: plan_declarations ────────────────────────────────────────────────
ALTER TABLE public.plan_declarations ADD COLUMN IF NOT EXISTS organization_id UUID;

DROP POLICY IF EXISTS "PlanDeclaration Insert" ON public.plan_declarations;
DROP POLICY IF EXISTS "PlanDeclaration Read" ON public.plan_declarations;

CREATE POLICY "PlanDeclaration Insert" ON public.plan_declarations
  FOR INSERT TO authenticated
  WITH CHECK (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid);

CREATE POLICY "PlanDeclaration Read" ON public.plan_declarations
  FOR SELECT TO authenticated
  USING (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid);

-- ── Block 4: execution_states ─────────────────────────────────────────────────
ALTER TABLE public.execution_states ADD COLUMN IF NOT EXISTS organization_id UUID;

DROP POLICY IF EXISTS "ExecutionState All" ON public.execution_states;

CREATE POLICY "ExecutionState tenant isolation" ON public.execution_states
  FOR ALL TO authenticated
  USING     (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid)
  WITH CHECK (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid);

-- ── Block 5: contractual_financial_snapshot (DROP + RECREATE) ────────────────
DROP TABLE IF EXISTS public.contractual_financial_snapshot CASCADE;

CREATE TABLE public.contractual_financial_snapshot (
  id                              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id                 UUID NOT NULL REFERENCES public.organizations(id),
  contract_id                     TEXT NOT NULL,
  operational_date_utc            DATE,
  operational_timezone            TEXT,
  closed_at_utc                   TIMESTAMPTZ,
  total_contracted_revenue_cents  BIGINT NOT NULL DEFAULT 0,
  protected_revenue_cents         BIGINT NOT NULL DEFAULT 0,
  revenue_at_risk_cents           BIGINT NOT NULL DEFAULT 0,
  lost_revenue_cents              BIGINT NOT NULL DEFAULT 0,
  risk_percentage                 FLOAT8,
  loss_percentage                 FLOAT8,
  total_obligations               INT,
  executed_count                  INT,
  no_show_count                   INT,
  evidence_gap_count              INT,
  last_ledger_entry_id            UUID,
  previous_snapshot_id            UUID,
  reprocessing_reason             TEXT,
  author_user_id                  UUID,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now())
);

ALTER TABLE public.contractual_financial_snapshot ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Snapshot tenant isolation select" ON public.contractual_financial_snapshot
  FOR SELECT TO authenticated
  USING (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid);

CREATE POLICY "Snapshot tenant isolation insert" ON public.contractual_financial_snapshot
  FOR INSERT TO authenticated
  WITH CHECK (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid);
