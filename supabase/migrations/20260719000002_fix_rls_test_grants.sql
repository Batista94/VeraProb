-- Migration: 20260719000002_fix_rls_test_grants.sql
-- Description: Restores SELECT/INSERT privileges for authenticated users on client-facing tables.

-- 1. execution_state_transitions (Required by client-side PostgresContractualExecutionStateRepository)
GRANT SELECT, INSERT ON TABLE public.execution_state_transitions TO authenticated;

-- 2. spoofing_audit_entries (Required by OCC visibility screen)
GRANT SELECT, INSERT ON TABLE public.spoofing_audit_entries TO authenticated;
