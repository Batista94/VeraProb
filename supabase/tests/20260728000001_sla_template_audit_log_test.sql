BEGIN;
SELECT plan(13);

-- Ensure the API role can read/append in this test DB (defensive).
GRANT SELECT, INSERT ON public.sla_template_audit_log TO authenticated;

-- ── Schema shape (INV-6) ───────────────────────────────────────────────────
SELECT has_column('public', 'sla_template_audit_log', 'id', 'id exists');
SELECT has_column('public', 'sla_template_audit_log', 'organization_id', 'organization_id exists');
SELECT has_column('public', 'sla_template_audit_log', 'template_snapshot', 'template_snapshot exists');
SELECT has_column('public', 'sla_template_audit_log', 'occurred_at_utc', 'occurred_at_utc exists');
SELECT col_type_is(
  'public', 'sla_template_audit_log', 'occurred_at_utc', 'timestamp with time zone',
  'occurred_at_utc is TIMESTAMPTZ (INV-6)'
);
SELECT col_type_is(
  'public', 'sla_template_audit_log', 'template_snapshot', 'jsonb',
  'template_snapshot is JSONB'
);

-- ── Immutability (INV-3) — superuser context: trigger fires, RLS bypassed ───
INSERT INTO public.sla_template_audit_log
  (organization_id, template_id, actor_session_id, action, template_snapshot)
VALUES
  ('a0000000-0000-0000-0000-00000000000a',
   'c0000000-0000-0000-0000-00000000000c',
   'sess-immut', 'CREATED', '{}'::jsonb);

SELECT throws_ok(
  $$ UPDATE public.sla_template_audit_log
       SET action = 'UPDATED' WHERE actor_session_id = 'sess-immut' $$,
  '23001',
  NULL,
  'UPDATE blocked — restrict_violation (INV-3)'
);

SELECT throws_ok(
  $$ DELETE FROM public.sla_template_audit_log
       WHERE actor_session_id = 'sess-immut' $$,
  '23001',
  NULL,
  'DELETE blocked — restrict_violation (INV-3)'
);

-- State immutability: prove the row was NOT mutated by the blocked ops above
-- (guards against a future AFTER-trigger refactor that would silently succeed).
SELECT results_eq(
  $$ SELECT action FROM public.sla_template_audit_log
       WHERE actor_session_id = 'sess-immut' $$,
  ARRAY['CREATED'],
  'row state unchanged after blocked UPDATE/DELETE (INV-3)'
);

-- ── Tenant isolation (INV-1, INV-2, INV-22) — authenticated role ────────────
SET LOCAL ROLE authenticated;

SET LOCAL request.jwt.claims =
  '{"role":"authenticated","app_metadata":{"org_id":"a0000000-0000-0000-0000-00000000000a"}}';
SELECT results_eq(
  'SELECT count(*)::int FROM public.sla_template_audit_log',
  ARRAY[1],
  'org_a sees its single row'
);

SET LOCAL request.jwt.claims =
  '{"role":"authenticated","app_metadata":{"org_id":"b0000000-0000-0000-0000-00000000000b"}}';
SELECT results_eq(
  'SELECT count(*)::int FROM public.sla_template_audit_log',
  ARRAY[0],
  'org_b is isolated from org_a (sees 0 rows)'
);

SELECT throws_ok(
  $$ INSERT INTO public.sla_template_audit_log
       (organization_id, template_id, actor_session_id, action, template_snapshot)
     VALUES ('a0000000-0000-0000-0000-00000000000a',
             'c0000000-0000-0000-0000-00000000000c',
             'sess-b', 'CREATED', '{}'::jsonb) $$,
  'new row violates row-level security policy for table "sla_template_audit_log"',
  'org_b cannot insert a row for org_a (RLS WITH CHECK)'
);

SELECT lives_ok(
  $$ INSERT INTO public.sla_template_audit_log
       (organization_id, template_id, actor_session_id, action, template_snapshot)
     VALUES ('b0000000-0000-0000-0000-00000000000b',
             'd0000000-0000-0000-0000-00000000000d',
             'sess-b', 'CREATED', '{}'::jsonb) $$,
  'org_b can insert its own row'
);

SELECT * FROM finish();
ROLLBACK;
