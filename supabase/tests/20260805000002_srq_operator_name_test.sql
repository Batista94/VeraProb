BEGIN;
SELECT plan(4);

-- 1. Column exists
SELECT has_column(
  'public',
  'sanction_review_queue',
  'operator_name',
  'sanction_review_queue has column operator_name'
);

-- Setup: organization required by the org_name auto-populate trigger.
INSERT INTO public.organizations (id, name, cnpj, created_at)
VALUES (
  'f0000000-0000-0000-0000-00000000000f',
  'Op Name Test Corp',
  '98.765.432/0001-11',
  NOW()
);

-- 2. Zero-Trust payload fallback (INV-18): a SANCTION_RECOMMENDED ledger entry
--    with no execution binding resolves operator_name/vehicle_plate from payload.
INSERT INTO public.sla_audit_ledger_v2 (
  organization_id, type, set_id, contract_id, plan_version, payload, occurred_at_utc
) VALUES (
  'f0000000-0000-0000-0000-00000000000f',
  'SANCTION_RECOMMENDED',
  'set_op_1',
  'a0000000-0000-0000-0000-0000000000a1',
  1,
  jsonb_build_object(
    'verdict_evidence', '{}'::jsonb,
    'vehicle_plate',    'TST-0001',
    'operator_name',    'João Silva'
  ),
  NOW()
);

SELECT is(
  (SELECT operator_name FROM public.sanction_review_queue WHERE set_id = 'set_op_1'),
  'João Silva',
  'operator_name resolved from Zero-Trust payload fallback'
);

SELECT is(
  (SELECT vehicle_plate FROM public.sanction_review_queue WHERE set_id = 'set_op_1'),
  'TST-0001',
  'vehicle_plate resolved from Zero-Trust payload fallback'
);

-- 3. Immutability guard (INV-1): operator_name cannot be mutated post-insert.
SELECT throws_ok(
  $$ UPDATE public.sanction_review_queue
        SET operator_name = 'Tampered'
      WHERE set_id = 'set_op_1' $$,
  '23001',
  NULL,
  'operator_name is immutable after insert (INV-1)'
);

SELECT * FROM finish();
ROLLBACK;
