-- =============================================================================
-- Test plan: 20260811000000_harden_client_role_grants
--
-- Asserts the post-migration least-privilege end-state for the Data API roles
-- (anon / authenticated) after revoking the legacy `ALTER DEFAULT PRIVILEGES`
-- `arwdDxtm` grant surface.
--
-- Pre-migration (proven via live introspection): anon/authenticated held TRUNCATE
-- on 30/8 public tables incl. the append-only ledger and evidence snapshots.
-- TRUNCATE is NOT gated by RLS, so an extracted anon key could wipe all tenants'
-- data + the immutable forensic ledger (INV-3, INV-22, availability).
-- =============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(16);

-- (1) No client role may TRUNCATE — RLS does not gate TRUNCATE (INV-22, availability)
SELECT ok(NOT has_table_privilege('anon', 'public.sla_audit_ledger_v2', 'TRUNCATE'),
  'anon cannot TRUNCATE the SLA ledger');
SELECT ok(NOT has_table_privilege('authenticated', 'public.sla_audit_ledger_p0', 'TRUNCATE'),
  'authenticated cannot TRUNCATE a ledger partition');
SELECT ok(NOT has_table_privilege('authenticated', 'public.forensic_evidence_snapshots', 'TRUNCATE'),
  'authenticated cannot TRUNCATE forensic evidence snapshots');
SELECT ok(NOT has_table_privilege('anon', 'public.contracts', 'TRUNCATE'),
  'anon cannot TRUNCATE contracts');
SELECT ok(NOT has_table_privilege('anon', 'public.vehicles', 'TRUNCATE'),
  'anon cannot TRUNCATE vehicles');

-- (2) Append-only ledger + evidence: client roles never UPDATE/DELETE (INV-3)
SELECT ok(NOT has_table_privilege('authenticated', 'public.sla_audit_ledger_v2', 'DELETE'),
  'authenticated cannot DELETE the ledger (INV-3 append-only)');
SELECT ok(NOT has_table_privilege('authenticated', 'public.sla_audit_ledger_v2', 'UPDATE'),
  'authenticated cannot UPDATE the ledger (INV-3 append-only)');
SELECT ok(NOT has_table_privilege('anon', 'public.sla_audit_ledger_p1', 'DELETE'),
  'anon cannot DELETE a ledger partition');
SELECT ok(NOT has_table_privilege('anon', 'public.forensic_evidence_snapshots', 'DELETE'),
  'anon cannot DELETE forensic evidence snapshots');

-- (3) anon stripped from tenant/business tables (no anon RLS policy; defense-in-depth)
SELECT ok(NOT has_table_privilege('anon', 'public.contracts', 'SELECT'),
  'anon has no SELECT on contracts');
SELECT ok(NOT has_table_privilege('anon', 'public.vehicles', 'INSERT'),
  'anon has no INSERT on vehicles');

-- (4) Legit public-flow token tables preserved (no regression)
SELECT ok(has_table_privilege('anon', 'public.contract_review_tokens', 'SELECT'),
  'anon retains SELECT on contract_review_tokens (public token flow)');
SELECT ok(has_table_privilege('anon', 'public.justification_submission_tokens', 'INSERT'),
  'anon retains INSERT on justification_submission_tokens (public submission flow)');

-- (5) service_role (trusted backend) unaffected
SELECT ok(has_table_privilege('service_role', 'public.sla_audit_ledger_v2', 'SELECT'),
  'service_role retains ledger access');

-- (6) SECURITY DEFINER search_path pinned (function_search_path_mutable / CWE-426)
SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'auto_enqueue_sanction_recommended'
      AND 'search_path=public' = ANY (p.proconfig)
  ),
  'auto_enqueue_sanction_recommended has a pinned search_path');
SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'create_execution_for_operator'
      AND 'search_path=public' = ANY (p.proconfig)
  ),
  'create_execution_for_operator has a pinned search_path');

SELECT * FROM finish();
ROLLBACK;
