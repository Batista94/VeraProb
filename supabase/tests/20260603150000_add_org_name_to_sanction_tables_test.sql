BEGIN;
SELECT plan(6);

-- 1. Check if column organization_name exists in sanction_review_queue
SELECT has_column(
  'public',
  'sanction_review_queue',
  'organization_name',
  'sanction_review_queue has column organization_name'
);

-- 2. Check if column organization_name exists in sanction_escalation_log
SELECT has_column(
  'public',
  'sanction_escalation_log',
  'organization_name',
  'sanction_escalation_log has column organization_name'
);

-- Setup test organization
INSERT INTO public.organizations (id, name, cnpj, created_at)
VALUES (
  'e0000000-0000-0000-0000-00000000000e',
  'Test Corp Forensic',
  '12.345.678/0001-99',
  NOW()
);

-- 3. Test insert in sanction_review_queue auto-populates organization_name
INSERT INTO public.sanction_review_queue (
  organization_id, ledger_entry_id, set_id, contract_id, verdict_evidence
) VALUES (
  'e0000000-0000-0000-0000-00000000000e',
  gen_random_uuid(),
  'set_tst_1',
  'contract_tst_1',
  '{}'::jsonb
);

SELECT is(
  (SELECT organization_name FROM public.sanction_review_queue WHERE set_id = 'set_tst_1'),
  'Test Corp Forensic',
  'sanction_review_queue organization_name is auto-populated via trigger'
);

-- 4. Test insert in sanction_escalation_log auto-populates organization_name
INSERT INTO public.sanction_escalation_log (
  organization_id, queue_entry_id, channel, delivery_status
) VALUES (
  'e0000000-0000-0000-0000-00000000000e',
  (SELECT id FROM public.sanction_review_queue WHERE set_id = 'set_tst_1'),
  'in_app',
  'sent'
);

SELECT is(
  (SELECT organization_name FROM public.sanction_escalation_log WHERE queue_entry_id = (SELECT id FROM public.sanction_review_queue WHERE set_id = 'set_tst_1')),
  'Test Corp Forensic',
  'sanction_escalation_log organization_name is auto-populated via trigger'
);

-- 5. Test backfill - update when name is NULL (verify behavior does not fail)
-- Temporarily set one row's organization_name to NULL
UPDATE public.sanction_review_queue
SET organization_name = NULL
WHERE set_id = 'set_tst_1';

-- Run the update statement from migration to check if it updates correctly
UPDATE public.sanction_review_queue AS srq
SET organization_name = o.name
FROM public.organizations o
WHERE srq.organization_id = o.id
  AND srq.organization_name IS NULL;

SELECT is(
  (SELECT organization_name FROM public.sanction_review_queue WHERE set_id = 'set_tst_1'),
  'Test Corp Forensic',
  'sanction_review_queue backfill updates organization_name correctly'
);

-- 6. Test escalation log backfill with trigger disabled/enabled
-- Temporarily disable immutability trigger and update organization_name to NULL
ALTER TABLE public.sanction_escalation_log DISABLE TRIGGER trg_sel_no_update;

UPDATE public.sanction_escalation_log
SET organization_name = NULL
WHERE queue_entry_id = (SELECT id FROM public.sanction_review_queue WHERE set_id = 'set_tst_1');

-- Run the migration update statement
UPDATE public.sanction_escalation_log AS sel
SET organization_name = o.name
FROM public.organizations o
WHERE sel.organization_id = o.id
  AND sel.organization_name IS NULL;

ALTER TABLE public.sanction_escalation_log ENABLE TRIGGER trg_sel_no_update;

SELECT is(
  (SELECT organization_name FROM public.sanction_escalation_log WHERE queue_entry_id = (SELECT id FROM public.sanction_review_queue WHERE set_id = 'set_tst_1')),
  'Test Corp Forensic',
  'sanction_escalation_log backfill updates organization_name correctly when trigger disabled'
);

SELECT * FROM finish();
ROLLBACK;
