-- Migration: 20260717000008_grant_tenant_access_tables.sql
-- Description: Applies explicit API grants to Tenant-Access (Standard Client) tables that were missing explicit grants.
-- Target: authenticated (SELECT, INSERT, UPDATE, DELETE), service_role (ALL)

DO $$ 
DECLARE
  target_table text;
  tables text[] := ARRAY[
    'organizations',
    'user_roles',
    'drivers',
    'invitations',
    'provider_api_keys',
    'csv_mapping_templates',
    'sla_templates',
    'sla_audit_ledger'
  ];
BEGIN
  FOREACH target_table IN ARRAY tables
  LOOP
    IF EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = target_table) THEN
      EXECUTE format('REVOKE ALL ON TABLE public.%I FROM public, anon, authenticated;', target_table);
      EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO authenticated;', target_table);
      EXECUTE format('GRANT ALL ON TABLE public.%I TO service_role;', target_table);
    END IF;
  END LOOP;
END $$;
