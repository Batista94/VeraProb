BEGIN;

SELECT plan(2);

-- Test 1: Verify financial:read description
SELECT results_eq(
  $$ SELECT description FROM public.tenant_permissions WHERE key = 'financial:read' $$,
  $$ VALUES ('Visualizar dados financeiros da organização'::text) $$,
  'financial:read description should use organization terminology'
);

-- Test 2: Verify contracts:read description
SELECT results_eq(
  $$ SELECT description FROM public.tenant_permissions WHERE key = 'contracts:read' $$,
  $$ VALUES ('Visualizar contratos da organização'::text) $$,
  'contracts:read description should use organization terminology'
);

SELECT * FROM finish();

ROLLBACK;
