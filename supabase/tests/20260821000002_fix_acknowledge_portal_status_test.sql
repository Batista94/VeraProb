BEGIN;
SELECT plan(8);

-- Setup Org
INSERT INTO public.organizations (id, name, cnpj)
VALUES ('11111111-1111-1111-1111-111111111111'::uuid, 'Test Org', '12345678901234');

-- Queue 1 (status: applied)
-- contract_id must be UUID-format text: acknowledge_via_portal does v_queue.contract_id::uuid
INSERT INTO public.sanction_review_queue (id, organization_id, vehicle_plate, verdict_evidence, status, ledger_entry_id, set_id, contract_id)
VALUES ('22222222-2222-2222-2222-222222222221', '11111111-1111-1111-1111-111111111111', 'ABC1234', '{}'::jsonb, 'applied',
        'b1000000-0000-0000-0000-000000000001'::uuid, 'set-ack-test', '00000000-0000-0000-0000-000000000099');

-- Queue 2 (status: disputed)
INSERT INTO public.sanction_review_queue (id, organization_id, vehicle_plate, verdict_evidence, status, ledger_entry_id, set_id, contract_id)
VALUES ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111', 'DEF5678', '{}'::jsonb, 'disputed',
        'b1000000-0000-0000-0000-000000000002'::uuid, 'set-ack-test', '00000000-0000-0000-0000-000000000099');

-- Queue 3 (status: pending - should fail)
INSERT INTO public.sanction_review_queue (id, organization_id, vehicle_plate, verdict_evidence, status, ledger_entry_id, set_id, contract_id)
VALUES ('22222222-2222-2222-2222-222222222223', '11111111-1111-1111-1111-111111111111', 'GHI9012', '{}'::jsonb, 'pending',
        'b1000000-0000-0000-0000-000000000003'::uuid, 'set-ack-test', '00000000-0000-0000-0000-000000000099');

-- Tokens
INSERT INTO public.dispute_portal_tokens (id, organization_id, queue_entry_id, token, access_count, max_access_count, expires_at_utc, created_by_user_id)
VALUES ('33333333-3333-3333-3333-333333333331', '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222221', '44444444-4444-4444-4444-444444444441', 0, 5, NOW() + INTERVAL '1 day', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid);

INSERT INTO public.dispute_portal_tokens (id, organization_id, queue_entry_id, token, access_count, max_access_count, expires_at_utc, created_by_user_id)
VALUES ('33333333-3333-3333-3333-333333333332', '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', '44444444-4444-4444-4444-444444444442', 0, 5, NOW() + INTERVAL '1 day', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid);

INSERT INTO public.dispute_portal_tokens (id, organization_id, queue_entry_id, token, access_count, max_access_count, expires_at_utc, created_by_user_id)
VALUES ('33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222223', '44444444-4444-4444-4444-444444444443', 0, 5, NOW() + INTERVAL '1 day', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid);

-- Ledger Entries to simulate token access
INSERT INTO public.sla_audit_ledger_v2 (organization_id, type, operator_id, set_id, contract_id, plan_version, payload, occurred_at_utc)
VALUES (
  '11111111-1111-1111-1111-111111111111', 'DISPUTE_PORTAL_TOKEN_ACCESSED', 'PORTAL', '00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000000', 0,
  '{"token_id": "33333333-3333-3333-3333-333333333331", "snapshot_hash": "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"}'::jsonb,
  NOW()
);

INSERT INTO public.sla_audit_ledger_v2 (organization_id, type, operator_id, set_id, contract_id, plan_version, payload, occurred_at_utc)
VALUES (
  '11111111-1111-1111-1111-111111111111', 'DISPUTE_PORTAL_TOKEN_ACCESSED', 'PORTAL', '00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000000', 0,
  '{"token_id": "33333333-3333-3333-3333-333333333332", "snapshot_hash": "b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3"}'::jsonb,
  NOW()
);

INSERT INTO public.sla_audit_ledger_v2 (organization_id, type, operator_id, set_id, contract_id, plan_version, payload, occurred_at_utc)
VALUES (
  '11111111-1111-1111-1111-111111111111', 'DISPUTE_PORTAL_TOKEN_ACCESSED', 'PORTAL', '00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000000', 0,
  '{"token_id": "33333333-3333-3333-3333-333333333333", "snapshot_hash": "c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4"}'::jsonb,
  NOW()
);


SET ROLE anon;

-- Test 1: Acknowledge 'applied' status
PREPARE ack_applied AS SELECT public.acknowledge_via_portal('44444444-4444-4444-4444-444444444441'::uuid, 'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2');
SELECT lives_ok('EXECUTE ack_applied', 'Acknowledging an applied sanction succeeds');

RESET ROLE;

-- Test 2: Status is now 'acknowledged' (must run as superuser — anon has no SELECT on sanction_review_queue)
PREPARE check_ack1 AS SELECT status FROM public.sanction_review_queue WHERE id = '22222222-2222-2222-2222-222222222221';
SELECT results_eq('EXECUTE check_ack1', $$VALUES ('acknowledged'::text)$$, 'Status updated to acknowledged');

SET ROLE anon;

-- Test 3: Idempotency (running it again succeeds and doesn't crash)
SELECT lives_ok('EXECUTE ack_applied', 'Idempotent call succeeds');

-- Test 4: Acknowledge 'disputed' status
PREPARE ack_disputed AS SELECT public.acknowledge_via_portal('44444444-4444-4444-4444-444444444442'::uuid, 'b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3');
SELECT lives_ok('EXECUTE ack_disputed', 'Acknowledging a disputed sanction succeeds');

RESET ROLE;

-- Test 5: Status is now 'acknowledged' (must run as superuser — anon has no SELECT on sanction_review_queue)
PREPARE check_ack2 AS SELECT status FROM public.sanction_review_queue WHERE id = '22222222-2222-2222-2222-222222222222';
SELECT results_eq('EXECUTE check_ack2', $$VALUES ('acknowledged'::text)$$, 'Status updated to acknowledged');

SET ROLE anon;

-- Failures
-- Test 6: Acknowledge 'pending' status fails
SELECT throws_ok(
  $$SELECT public.acknowledge_via_portal('44444444-4444-4444-4444-444444444443'::uuid, 'c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4')$$,
  '42501',
  'Acknowledgement rejected.',
  'Pending queue status returns 42501'
);

-- Test 7: Wrong hash returns 42501
SELECT throws_ok(
  $$SELECT public.acknowledge_via_portal('44444444-4444-4444-4444-444444444441'::uuid, 'wronghashc3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f')$$,
  '42501',
  'Acknowledgement rejected.',
  'Wrong hash returns 42501'
);

-- Test 8: Null hash returns 42501
SELECT throws_ok(
  $$SELECT public.acknowledge_via_portal('44444444-4444-4444-4444-444444444441'::uuid, NULL)$$,
  '42501',
  'Acknowledgement rejected.',
  'Null hash returns 42501'
);

RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
