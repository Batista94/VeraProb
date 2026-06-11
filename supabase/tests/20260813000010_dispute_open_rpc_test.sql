BEGIN;
SELECT plan(6);

-- Setup
INSERT INTO public.organizations (id, name, created_at, updated_at) VALUES ('org_dispute_1', 'Org 1', now(), now());
INSERT INTO public.contracts (id, organization_id, name, config, created_at, updated_at) VALUES ('contract_dispute_1', 'org_dispute_1', 'Contract 1', '{}', now(), now());

-- Mock a pending queue entry
INSERT INTO public.sanction_review_queue (
    id, organization_id, ledger_entry_id, set_id, contract_id, status, verdict_evidence
) VALUES (
    'queue_dispute_1', 'org_dispute_1', 'ledger_dispute_1', 'set_dispute_1', 'contract_dispute_1', 'pending', '{}'
);

-- Test 1: Successful dispute
SELECT lives_ok(
    $$ SELECT public.dispute_sanction('org_dispute_1', 'queue_dispute_1', 'user_auditor_1', 'auditor@test.com', now()) $$,
    'dispute_sanction completes without error'
);

-- Test 2: Status is updated
SELECT results_eq(
    $$ SELECT status::text FROM public.sanction_review_queue WHERE id = 'queue_dispute_1' $$,
    $$ VALUES ('disputed') $$,
    'status is updated to disputed'
);

-- Test 3: SLA is set
SELECT isnt_empty(
    $$ SELECT id FROM public.sanction_review_queue WHERE id = 'queue_dispute_1' AND resolution_due_at IS NOT NULL $$,
    'resolution_due_at is set'
);

-- Test 4: Ledger entry created
SELECT results_eq(
    $$ SELECT type FROM public.sla_audit_ledger_v2 WHERE payload->>'queue_entry_id' = 'queue_dispute_1' AND type = 'SANCTION_DISPUTED' $$,
    $$ VALUES ('SANCTION_DISPUTED') $$,
    'ledger entry SANCTION_DISPUTED created'
);

-- Test 5: Idempotency (already disputed)
SELECT throws_like(
    $$ SELECT public.dispute_sanction('org_dispute_1', 'queue_dispute_1', 'user_auditor_1', 'auditor@test.com', now()) $$,
    '%already been reviewed%',
    'should fail if not pending'
);

-- Test 6: Wrong org
SELECT throws_like(
    $$ SELECT public.dispute_sanction('org_wrong', 'queue_dispute_1', 'user_auditor_1', 'auditor@test.com', now()) $$,
    '%Sanction review rejected%',
    'should fail if wrong org'
);

SELECT * FROM finish();
ROLLBACK;
