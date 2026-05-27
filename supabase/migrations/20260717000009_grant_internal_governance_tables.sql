-- Migration: 20260717000009_grant_internal_governance_tables.sql
-- Description: Applies explicit API grants to Internal-Governance (Category C) tables that were missing explicit grants.
-- Target: service_role (ALL). All privileges are revoked from anon and authenticated.

DO $$ 
DECLARE
  target_table text;
  tables text[] := ARRAY[
    'raw_telemetry_payloads',
    'asset_status_events',
    'canonical_facts',
    'audit_packages',
    'org_quota_warnings',
    'ingestion_alerts',
    'contractual_evaluation_traces',
    'contractual_financial_snapshot_v2',
    'execution_state_transitions'
  ];
BEGIN
  FOREACH target_table IN ARRAY tables
  LOOP
    IF EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = target_table) THEN
      EXECUTE format('REVOKE ALL ON TABLE public.%I FROM public, anon, authenticated;', target_table);
      EXECUTE format('GRANT ALL ON TABLE public.%I TO service_role;', target_table);
    END IF;
  END LOOP;
END $$;
