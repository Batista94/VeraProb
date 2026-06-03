BEGIN;

SELECT plan(7);

-- Test setup: create test org and traces
INSERT INTO public.organizations (id, name, created_at)
VALUES ('00000000-0000-0000-0000-000000000001', 'Test Org 1', now())
ON CONFLICT DO NOTHING;

INSERT INTO public.organizations (id, name, created_at)
VALUES ('00000000-0000-0000-0000-000000000002', 'Test Org 2', now())
ON CONFLICT DO NOTHING;

-- Insert traces (requires temporarily disabling RLS or acting as postgres/service_role, which pgTAP does by default)
INSERT INTO public.contractual_evaluation_traces (
  organization_id, set_id, contract_id, triggering_event_id, 
  engine_version, evaluated_at_utc, decisions
)
VALUES 
  ('00000000-0000-0000-0000-000000000001', 'set-1', 'contract-1', 'event-1', 'v1.0.0', now(), '[]'::jsonb),
  ('00000000-0000-0000-0000-000000000002', 'set-2', 'contract-2', 'event-2', 'v1.0.0', now(), '[]'::jsonb);

-- Set role to authenticated for test execution
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"app_metadata": {"org_id": "00000000-0000-0000-0000-000000000001"}}';

-- TC-1: Authenticated SELECT — Own Org (Happy Path)
SELECT results_eq(
  $$ SELECT set_id FROM public.contractual_evaluation_traces $$,
  ARRAY['set-1'],
  'Authenticated user can read evaluation traces for their own organization'
);

-- TC-2: Authenticated SELECT — Cross-Tenant (INV-22 + INV-26)
SET LOCAL request.jwt.claims = '{"app_metadata": {"org_id": "00000000-0000-0000-0000-000000000003"}}';
SELECT is_empty(
  $$ SELECT set_id FROM public.contractual_evaluation_traces $$,
  'Authenticated user cannot read evaluation traces from other organizations (INV-22)'
);

-- TC-3: Authenticated INSERT — Still Permitted
SET LOCAL request.jwt.claims = '{"app_metadata": {"org_id": "00000000-0000-0000-0000-000000000001"}}';
SELECT lives_ok(
  $$ 
  INSERT INTO public.contractual_evaluation_traces (
    organization_id, set_id, contract_id, triggering_event_id, 
    engine_version, evaluated_at_utc, decisions
  )
  VALUES ('00000000-0000-0000-0000-000000000001', 'set-3', 'contract-3', 'event-3', 'v1.0.0', now(), '[]'::jsonb);
  $$,
  'Authenticated user can insert new evaluation traces'
);

-- TC-4: Authenticated UPDATE — Remains Blocked (INV-3)
SELECT throws_ok(
  $$ UPDATE public.contractual_evaluation_traces SET engine_version = 'v2.0.0' WHERE set_id = 'set-1' $$,
  '42501',
  NULL,
  'Authenticated user cannot update evaluation traces (INV-3 append-only)'
);

-- TC-5: Authenticated DELETE — Remains Blocked (INV-3)
SELECT throws_ok(
  $$ DELETE FROM public.contractual_evaluation_traces WHERE set_id = 'set-1' $$,
  '42501',
  NULL,
  'Authenticated user cannot delete evaluation traces (INV-3 append-only)'
);

-- TC-6: Anon SELECT — Remains Blocked
SET LOCAL ROLE anon;
SET LOCAL request.jwt.claims = '';
SELECT throws_ok(
  $$ SELECT set_id FROM public.contractual_evaluation_traces $$,
  '42501',
  NULL,
  'Anon user cannot read evaluation traces'
);

-- Verify the explicit GRANT for authenticated
SELECT table_privs_are(
  'public',
  'contractual_evaluation_traces',
  'authenticated',
  ARRAY['SELECT', 'INSERT'],
  'Authenticated role has explicit SELECT and INSERT privileges'
);

SELECT * FROM finish();
ROLLBACK;
