BEGIN;
SELECT plan(7);
SELECT has_function('public', 'dispute_sanction', ARRAY['uuid', 'uuid', 'uuid', 'text', 'timestamp with time zone'], 'Function dispute_sanction exists');

-- Setup
INSERT INTO public.organizations (id, name) VALUES ('11111111-1111-4111-8111-111111111111', 'Org 1');
INSERT INTO public.contracts (id, organization_id, name, contractor_name, valid_from_utc, valid_until_utc, status) VALUES ('22222222-2222-4222-8222-222222222222', '11111111-1111-4111-8111-111111111111', 'Contract 1', 'Contractor 1', now(), now() + INTERVAL '1 year', 'active');

-- Mock a pending queue entry
INSERT INTO public.sanction_review_queue (
    id, organization_id, ledger_entry_id, set_id, contract_id, status, verdict_evidence
) VALUES (
    '33333333-3333-4333-8333-333333333333', '11111111-1111-4111-8111-111111111111', '44444444-4444-4444-8444-444444444444', '55555555-5555-4555-8555-555555555555', '22222222-2222-4222-8222-222222222222', 'pending', '{}'
);

-- Setup JWT Claims
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"role":"authenticated","sub":"66666666-6666-4666-8666-666666666666","organization_id":"11111111-1111-4111-8111-111111111111","app_metadata":{"org_id":"11111111-1111-4111-8111-111111111111","role":"AUDITOR"}}';

-- Test 1: Successful dispute
SELECT lives_ok(
    $$ SELECT public.dispute_sanction('11111111-1111-4111-8111-111111111111'::uuid, '33333333-3333-4333-8333-333333333333'::uuid, '66666666-6666-4666-8666-666666666666'::uuid, 'auditor@test.com'::text, now()::timestamptz) $$,
    'dispute_sanction completes without error'
);

-- Test 2: Status is updated
SELECT results_eq(
    $$ SELECT status::text FROM public.sanction_review_queue WHERE id = '33333333-3333-4333-8333-333333333333' $$,
    $$ VALUES ('disputed') $$,
    'status is updated to disputed'
);

-- Test 3: SLA is set
SELECT isnt_empty(
    $$ SELECT id FROM public.sanction_review_queue WHERE id = '33333333-3333-4333-8333-333333333333' AND resolution_due_at IS NOT NULL $$,
    'resolution_due_at is set'
);

-- Test 4: Ledger entry created
SELECT results_eq(
    $$ SELECT type::text FROM public.sla_audit_ledger_v2 WHERE payload->>'queue_entry_id' = '33333333-3333-4333-8333-333333333333' AND type = 'SANCTION_DISPUTED' $$,
    $$ VALUES ('SANCTION_DISPUTED'::text) $$,
    'ledger entry SANCTION_DISPUTED created'
);

-- Test 5: Idempotency (already disputed)
SELECT throws_like(
    $$ SELECT public.dispute_sanction('11111111-1111-4111-8111-111111111111'::uuid, '33333333-3333-4333-8333-333333333333'::uuid, '66666666-6666-4666-8666-666666666666'::uuid, 'auditor@test.com'::text, now()::timestamptz) $$,
    '%This sanction has already been reviewed by another auditor.%',
    'should fail if not pending'
);

-- Test 6: Wrong org
SELECT throws_like(
    $$ SELECT public.dispute_sanction('77777777-7777-4777-8777-777777777777'::uuid, '33333333-3333-4333-8333-333333333333'::uuid, '66666666-6666-4666-8666-666666666666'::uuid, 'auditor@test.com'::text, now()::timestamptz) $$,
    '%Dispute rejected.%',
    'should fail if wrong org'
);

SELECT * FROM finish();
ROLLBACK;
