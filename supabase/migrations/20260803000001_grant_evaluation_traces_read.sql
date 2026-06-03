-- Migration: 20260803000001_grant_evaluation_traces_read.sql
-- Description: Re-grants SELECT to authenticated for contractual_evaluation_traces.
-- Root Cause: 20260717000009 (grant_internal_governance_tables) classified this table
-- as Category C (service_role-only), but the InvestigationModal requires authenticated
-- read access. RLS policies already enforce tenant isolation (org_id JWT path, fixed
-- in 20260310210000).
-- Invariants: INV-DATA-API-GRANT, INV-2 (RLS enforced), INV-22 (tenant isolation).

GRANT SELECT ON TABLE public.contractual_evaluation_traces TO authenticated;
-- service_role already has ALL via 20260717000009. No change needed.
