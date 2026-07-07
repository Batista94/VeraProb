BEGIN;

SELECT plan(3);

-- Test 1: Verify Resolution Categorization
SELECT results_eq(
  $$ SELECT applies_to FROM public.dispute_reason_codes WHERE code = 'SENSOR_FAULT' $$,
  $$ VALUES ('RESOLUTION') $$,
  'SENSOR_FAULT should be categorized as RESOLUTION'
);

-- Test 2: Verify Rejection Insertion
SELECT results_eq(
  $$ SELECT applies_to FROM public.dispute_reason_codes WHERE code = 'INSUFFICIENT_EVIDENCE' $$,
  $$ VALUES ('REJECTION') $$,
  'INSUFFICIENT_EVIDENCE should be categorized as REJECTION'
);

-- Test 3: Verify Unaffected Codes remain ALL
SELECT results_eq(
  $$ SELECT applies_to FROM public.dispute_reason_codes WHERE code = 'OTHER' $$,
  $$ VALUES ('ALL') $$,
  'OTHER should remain categorized as ALL'
);

SELECT * FROM finish();

ROLLBACK;
