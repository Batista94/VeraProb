-- ============================================================
-- PactaFlow — Phase 6: RLS JWT Path Unification (INV-10)
-- ============================================================
-- REASON:
--   Unify all Row-Level Security policies to use the canonical
--   path for organization isolation injected by the custom hook:
--     (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid
-- ============================================================

-- 1. Refresh custom_access_token_hook (SECURITY DEFINER)
-- This ensures the hook is always up to date with the latest logic.
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

-- 2. Helper function to drop all policies for a table (Idempotency)
CREATE OR REPLACE FUNCTION drop_all_policies_for_table(target_table text) 
RETURNS void AS $$
DECLARE
    pol record;
BEGIN
    FOR pol IN 
        SELECT policyname 
        FROM pg_policies 
        WHERE schemaname = 'public' AND tablename = target_table
    LOOP
        EXECUTE format('DROP POLICY %I ON public.%I', pol.policyname, target_table);
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- 3. Unify RLS for all critical tables

-- ── organizations ──────────────────────────────────────────
SELECT drop_all_policies_for_table('organizations');
ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Tenant Isolation: organizations" ON public.organizations
  FOR SELECT USING (id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid);

-- ── user_roles ──────────────────────────────────────────────
SELECT drop_all_policies_for_table('user_roles');
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Tenant Isolation: user_roles" ON public.user_roles
  FOR SELECT USING (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid);

-- ── sla_audit_ledger_v2 ─────────────────────────────────────
SELECT drop_all_policies_for_table('sla_audit_ledger_v2');
ALTER TABLE public.sla_audit_ledger_v2 ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Tenant Isolation: sla_audit_ledger_v2" ON public.sla_audit_ledger_v2
  FOR ALL USING (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid)
  WITH CHECK (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid);

-- ── contractual_financial_snapshot_v2 ──────────────────────
SELECT drop_all_policies_for_table('contractual_financial_snapshot_v2');
ALTER TABLE public.contractual_financial_snapshot_v2 ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Tenant Isolation: financial_snapshots" ON public.contractual_financial_snapshot_v2
  FOR SELECT USING (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid);

-- ── contract_rule_sets ─────────────────────────────────────
SELECT drop_all_policies_for_table('contract_rule_sets');
ALTER TABLE public.contract_rule_sets ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Tenant Isolation: rule_sets" ON public.contract_rule_sets
  FOR ALL USING (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid)
  WITH CHECK (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid);

-- ── contract_rule_versions ──────────────────────────────────
SELECT drop_all_policies_for_table('contract_rule_versions');
ALTER TABLE public.contract_rule_versions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Tenant Isolation: rule_versions" ON public.contract_rule_versions
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM public.contract_rule_sets
      WHERE id = contract_rule_versions.rule_set_id
        AND organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid
    )
  );

-- ── operational_alerts ──────────────────────────────────────
SELECT drop_all_policies_for_table('operational_alerts');
ALTER TABLE public.operational_alerts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Tenant Isolation: alerts" ON public.operational_alerts
  FOR ALL USING (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid)
  WITH CHECK (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid);

-- ── operational_zones ───────────────────────────────────────
SELECT drop_all_policies_for_table('operational_zones');
ALTER TABLE public.operational_zones ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Tenant Isolation: zones" ON public.operational_zones
  FOR ALL USING (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid)
  WITH CHECK (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid);

-- ── contractual_service_executions ──────────────────────────
SELECT drop_all_policies_for_table('contractual_service_executions');
ALTER TABLE public.contractual_service_executions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Tenant Isolation: executions" ON public.contractual_service_executions
  FOR ALL USING (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid)
  WITH CHECK (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid);

-- ── plan_declarations ───────────────────────────────────────
SELECT drop_all_policies_for_table('plan_declarations');
ALTER TABLE public.plan_declarations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Tenant Isolation: plans" ON public.plan_declarations
  FOR ALL USING (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid)
  WITH CHECK (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid);

-- ── contracts ───────────────────────────────────────────────
SELECT drop_all_policies_for_table('contracts');
ALTER TABLE public.contracts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Tenant Isolation: contracts" ON public.contracts
  FOR ALL USING (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid)
  WITH CHECK (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid);

-- 4. Cleanup helper function
DROP FUNCTION drop_all_policies_for_table(text);
