BEGIN;

SELECT plan(7);

-- Test setup: create test orgs and traces.
-- pgTAP runs as the superuser (postgres) here, bypassing grants + RLS for seeding.
-- Real columns: organization_id, entity_id, triggering_event_id (uuid),
--               engine_version, evaluated_at_utc, decisions_jsonb.
INSERT INTO public.organizations (id, name, created_at)
VALUES ('00000000-0000-0000-0000-000000000001', 'Test Org 1', now())
ON CONFLICT DO NOTHING;

INSERT INTO public.organizations (id, name, created_at)
VALUES ('00000000-0000-0000-0000-000000000002', 'Test Org 2', now())
ON CONFLICT DO NOTHING;

INSERT INTO public.contractual_evaluation_traces (
  organization_id, entity_id, triggering_event_id,
  engine_version, evaluated_at_utc, decisions_jsonb
)
VALUES
  ('00000000-0000-0000-0000-000000000001', 'set-1', gen_random_uuid(), 'v1.0.0', now(), '[]'::jsonb),
  ('00000000-0000-0000-0000-000000000002', 'set-2', gen_random_uuid(), 'v1.0.0', now(), '[]'::jsonb);

-- Act as authenticated for the tenant-scoped assertions.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"app_metadata": {"org_id": "00000000-0000-0000-0000-000000000001"}}';

-- TC-1: Authenticated SELECT — Own Org (Happy Path)
SELECT results_eq(
  $$ SELECT entity_id FROM public.contractual_evaluation_traces $$,
  ARRAY['set-1'],
  'Authenticated user can read evaluation traces for their own organization'
);

-- TC-2: Authenticated SELECT — Cross-Tenant returns empty (INV-22 + INV-26)
SET LOCAL request.jwt.claims = '{"app_metadata": {"org_id": "00000000-0000-0000-0000-000000000003"}}';
SELECT is_empty(
  $$ SELECT entity_id FROM public.contractual_evaluation_traces $$,
  'Authenticated user cannot read evaluation traces from other organizations (INV-22)'
);

-- TC-3: Authenticated INSERT — Blocked (SELECT-only grant; engine writes via service_role)
SET LOCAL request.jwt.claims = '{"app_metadata": {"org_id": "00000000-0000-0000-0000-000000000001"}}';
SELECT throws_ok(
  $$
  INSERT INTO public.contractual_evaluation_traces (
    organization_id, entity_id, triggering_event_id,
    engine_version, evaluated_at_utc, decisions_jsonb
  )
  VALUES ('00000000-0000-0000-0000-000000000001', 'set-3', gen_random_uuid(), 'v1.0.0', now(), '[]'::jsonb);
  $$,
  '42501',
  NULL,
  'Authenticated user cannot insert evaluation traces (SELECT-only; service_role writes)'
);

-- TC-4: Authenticated UPDATE — Blocked (INV-3 append-only)
SELECT throws_ok(
  $$ UPDATE public.contractual_evaluation_traces SET engine_version = 'v2.0.0' WHERE entity_id = 'set-1' $$,
  '42501',
  NULL,
  'Authenticated user cannot update evaluation traces (INV-3 append-only)'
);

-- TC-5: Authenticated DELETE — Blocked (INV-3 append-only)
SELECT throws_ok(
  $$ DELETE FROM public.contractual_evaluation_traces WHERE entity_id = 'set-1' $$,
  '42501',
  NULL,
  'Authenticated user cannot delete evaluation traces (INV-3 append-only)'
);

-- TC-6: Anon — no read access (grant-level; service-only table)
SELECT ok(
  NOT has_table_privilege('anon', 'public.contractual_evaluation_traces', 'SELECT'),
  'Anon has no SELECT privilege on evaluation traces'
);

-- TC-7: Explicit grant surface — authenticated has SELECT only
SELECT table_privs_are(
  'public',
  'contractual_evaluation_traces',
  'authenticated',
  ARRAY['SELECT'],
  'Authenticated role has SELECT-only privilege on contractual_evaluation_traces'
);

SELECT * FROM finish();
ROLLBACK;
