-- pr_scanner: ignore-regression (companion test for 20260822000003)
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(4);

-- =============================================================================
-- pgTAP: fix_test_cleanup_fk_order companion test
-- Migration: 20260822000003_fix_test_cleanup_fk_order.sql
-- Focus: Verify test_cleanup_forensic_data deletes FK-child dispute portal
--        tables BEFORE sanction_review_queue, avoiding 23503 violations.
-- INV-2, INV-22.
-- =============================================================================

INSERT INTO public.organizations (id, name, cnpj) VALUES
  ('ee000000-0000-0000-0000-000000000010'::uuid, 'EE FK Order Test Org', '44444444444401')
ON CONFLICT (id) DO NOTHING;

-- Parent row (INSERT is not blocked by append-only trigger)
INSERT INTO public.sanction_review_queue
  (id, organization_id, ledger_entry_id, set_id, contract_id,
   verdict_evidence, status, vehicle_plate)
VALUES (
  'ee000000-0000-0000-0000-000000000020'::uuid,
  'ee000000-0000-0000-0000-000000000010'::uuid,
  'ee000000-0000-0000-0000-000000000f20'::uuid,
  'set-ee', 'ee-contract',
  jsonb_build_object(
    'fine_cents', 10000,
    'primary_evidence_timestamp_utc', '2026-08-22T10:00:00Z'
  ),
  'pending', 'EE-001'
)
ON CONFLICT (id) DO NOTHING;

-- FK child: must be deleted BEFORE sanction_review_queue
INSERT INTO public.dispute_portal_tokens
  (token, organization_id, queue_entry_id, created_by_user_id,
   expires_at_utc, max_access_count, created_at_utc)
VALUES (
  'ee000001-0000-0000-0000-000000000000'::uuid,
  'ee000000-0000-0000-0000-000000000010'::uuid,
  'ee000000-0000-0000-0000-000000000020'::uuid,
  'ee000000-0000-0000-0000-0000000000a1'::uuid,
  NOW() + INTERVAL '24 hours', 5, NOW()
)
ON CONFLICT (token) DO NOTHING;

-- T1: function exists with correct signature
SELECT has_function(
  'public', 'test_cleanup_forensic_data', ARRAY['uuid'],
  'T1: test_cleanup_forensic_data(uuid) exists in public schema'
);

-- T2: authenticated role cannot execute (REVOKE FROM PUBLIC, GRANT TO service_role only)
SELECT ok(
  NOT has_function_privilege('authenticated', 'public.test_cleanup_forensic_data(uuid)', 'execute'),
  'T2: authenticated cannot execute test_cleanup_forensic_data (service_role only)'
);

-- T3: FK deletion order — function completes without 23503 when dispute_portal_tokens
--     child row exists (regression: old definition deleted queue before portal children)
SELECT lives_ok(
  $$ SELECT public.test_cleanup_forensic_data('ee000000-0000-0000-0000-000000000010'::uuid) $$,
  'T3: no FK violation — dispute_portal_tokens deleted before sanction_review_queue'
);

-- T4: sanction_review_queue fully cleaned for the test org
SELECT is(
  (SELECT COUNT(*)::int FROM public.sanction_review_queue
   WHERE organization_id = 'ee000000-0000-0000-0000-000000000010'::uuid),
  0,
  'T4: sanction_review_queue emptied after test_cleanup_forensic_data call'
);

SELECT * FROM finish();
ROLLBACK;
