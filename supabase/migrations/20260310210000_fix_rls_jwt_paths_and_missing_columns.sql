-- Migration: Fix all RLS JWT path issues and missing columns
-- Root cause: multiple migrations used wrong JWT claim path.
-- The custom_access_token_hook injects org_id under app_metadata:
--   CORRECT: (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid
--   WRONG:   (auth.jwt() ->> 'organization_id')::uuid  -- wrong key, wrong nesting
--   WRONG:   (auth.jwt() ->> 'org_id')::uuid           -- correct key, wrong nesting
--   WRONG:   (... -> 'app_metadata' ->> 'organization_id')::uuid -- correct path, wrong key

-- ── 1. sla_audit_ledger_v2 — missing contract_id column ──────────────────────
-- postgres_sla_audit_ledger_repository.dart inserts contract_id but column was never created.
ALTER TABLE public.sla_audit_ledger_v2
  ADD COLUMN IF NOT EXISTS contract_id UUID;

-- ── 2. contract_rule_sets — wrong JWT path ────────────────────────────────────
DROP POLICY IF EXISTS "Tenants can manage their own rule sets" ON public.contract_rule_sets;

CREATE POLICY "Tenants can manage their own rule sets"
  ON public.contract_rule_sets
  FOR ALL
  USING     (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid)
  WITH CHECK (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid);

-- ── 3. contract_rule_versions — wrong JWT path (via subquery on rule_sets) ───
DROP POLICY IF EXISTS "Tenants can manage their own rule versions based on set ownership"
  ON public.contract_rule_versions;

CREATE POLICY "Tenants can manage their own rule versions based on set ownership"
  ON public.contract_rule_versions
  FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.contract_rule_sets
      WHERE id = contract_rule_versions.rule_set_id
        AND organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.contract_rule_sets
      WHERE id = contract_rule_versions.rule_set_id
        AND organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid
    )
  );

-- ── 4. operational_alerts — wrong JWT path (3 policies) ──────────────────────
DROP POLICY IF EXISTS "org_isolation_select" ON public.operational_alerts;
DROP POLICY IF EXISTS "org_isolation_insert" ON public.operational_alerts;
DROP POLICY IF EXISTS "org_isolation_update" ON public.operational_alerts;

CREATE POLICY "org_isolation_select" ON public.operational_alerts
  FOR SELECT USING (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid);

CREATE POLICY "org_isolation_insert" ON public.operational_alerts
  FOR INSERT WITH CHECK (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid);

CREATE POLICY "org_isolation_update" ON public.operational_alerts
  FOR UPDATE USING (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid);

-- ── 5. contractual_evaluation_traces — wrong key in app_metadata ─────────────
-- Used 'organization_id' key but hook injects 'org_id'.
DROP POLICY IF EXISTS "Tenant Isolation: Maintainers can read their traces"
  ON public.contractual_evaluation_traces;
DROP POLICY IF EXISTS "Tenant Isolation: Maintainers can insert their traces"
  ON public.contractual_evaluation_traces;

CREATE POLICY "Tenant Isolation: Maintainers can read their traces"
  ON public.contractual_evaluation_traces
  FOR SELECT
  USING (
    organization_id = (current_setting('request.jwt.claims', true)::json -> 'app_metadata' ->> 'org_id')::uuid
  );

CREATE POLICY "Tenant Isolation: Maintainers can insert their traces"
  ON public.contractual_evaluation_traces
  FOR INSERT
  WITH CHECK (
    organization_id = (current_setting('request.jwt.claims', true)::json -> 'app_metadata' ->> 'org_id')::uuid
  );

-- ── 6. contractual_financial_snapshot (v1) — top-level jwt claim, wrong nesting
DROP POLICY IF EXISTS "Users can view their organization snapshots"
  ON public.contractual_financial_snapshot;
DROP POLICY IF EXISTS "Users can insert their organization snapshots"
  ON public.contractual_financial_snapshot;

CREATE POLICY "Users can view their organization snapshots"
  ON public.contractual_financial_snapshot
  FOR SELECT
  USING (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid);

CREATE POLICY "Users can insert their organization snapshots"
  ON public.contractual_financial_snapshot
  FOR INSERT
  WITH CHECK (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid);
