-- =============================================================================
-- pgTAP: 20260923000004_portal_submissions_unified_view
-- CIA: C — security_invoker + kinds + deny-all isolation via invoker
-- =============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(6);

SELECT has_view('public', 'portal_submissions_unified', 'unified portal view exists');

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relname = 'portal_submissions_unified'
      AND c.relkind = 'v'
      AND 'security_invoker=true' = ANY (c.reloptions)
  ),
  'portal_submissions_unified has security_invoker=true'
);

SELECT has_column('public', 'portal_submissions_unified', 'submission_kind',
  'submission_kind column present');

-- Seed twin rows (service_role / postgres bypasses deny-all)
INSERT INTO public.organizations (
  id, name, legal_name, cnpj, timezone, currency_code, plan_type, max_vehicles,
  max_active_contracts, tool_cost_cents, dwell_time_seconds, billing_day,
  contact_email, external_id, organization_type, allowed_domains
) VALUES (
  '00000000-0000-0000-0000-00000000c4a1', 'Org View CIA', 'Org View CIA SA',
  '0000000000c4a1', 'America/Sao_Paulo', 'BRL', 'enterprise', 1000, 50, 15000, 300, 15,
  'view-cia@test.com', 'EXT_C4', 'LOGISTICS', ARRAY['test.com']
) ON CONFLICT (id) DO NOTHING;

INSERT INTO public.sanction_review_queue
  (id, organization_id, ledger_entry_id, set_id, contract_id, verdict_evidence, status,
   disputed_at, disputed_by, resolution_due_at)
VALUES (
  '00000000-0000-0000-0000-00000000c4e1',
  '00000000-0000-0000-0000-00000000c4a1',
  '00000000-0000-0000-0000-00000000c4f1',
  'set-c4',
  '00000000-0000-0000-0000-00000000c4aa',
  '{"rule_type":"MAX_TOLERANCE_DELAY","description":"D"}'::jsonb,
  'disputed', NOW(), '00000000-0000-0000-0000-00000000c4b1', NOW() + INTERVAL '5 days'
) ON CONFLICT (id) DO NOTHING;

INSERT INTO public.dispute_portal_tokens
  (id, organization_id, queue_entry_id, created_by_user_id, expires_at_utc,
   max_access_count, token_scope, max_submissions, created_at_utc)
VALUES (
  '00000000-0000-0000-0000-00000000c401',
  '00000000-0000-0000-0000-00000000c4a1',
  '00000000-0000-0000-0000-00000000c4e1',
  '00000000-0000-0000-0000-00000000c4b1',
  NOW() + INTERVAL '24 hours', 5, 'submit', 5, NOW()
) ON CONFLICT (id) DO NOTHING;

INSERT INTO public.portal_evidence_submissions
  (id, organization_id, queue_entry_id, token_id, quarantine_storage_path,
   file_name, mime_type_declared, file_size_bytes_declared, sha256_client, status)
VALUES (
  '00000000-0000-0000-0000-00000000c451',
  '00000000-0000-0000-0000-00000000c4a1',
  '00000000-0000-0000-0000-00000000c4e1',
  '00000000-0000-0000-0000-00000000c401',
  '00000000-0000-0000-0000-00000000c4t1/a.pdf',
  'a.pdf', 'application/pdf', 2048, repeat('a', 64), 'QUARANTINE'
) ON CONFLICT (id) DO NOTHING;

INSERT INTO public.portal_justification_submissions
  (id, organization_id, queue_entry_id, token_id, justification_text, sha256_justification_seal)
VALUES (
  '00000000-0000-0000-0000-00000000c452',
  '00000000-0000-0000-0000-00000000c4a1',
  '00000000-0000-0000-0000-00000000c4e1',
  '00000000-0000-0000-0000-00000000c401',
  'Justificativa minima para seed da view unificada.',
  repeat('b', 64)
) ON CONFLICT (id) DO NOTHING;

SELECT is(
  (SELECT count(DISTINCT submission_kind)::int
     FROM public.portal_submissions_unified
    WHERE organization_id = '00000000-0000-0000-0000-00000000c4a1'),
  2,
  'unified view returns both evidence and justification kinds'
);

SELECT ok(
  (SELECT count(*)::int FROM public.portal_submissions_unified
    WHERE organization_id = '00000000-0000-0000-0000-00000000c4a1'
      AND submission_kind = 'evidence') = 1
  AND
  (SELECT count(*)::int FROM public.portal_submissions_unified
    WHERE organization_id = '00000000-0000-0000-0000-00000000c4a1'
      AND submission_kind = 'justification') = 1,
  'one evidence + one justification row visible to definer/postgres'
);

-- Authenticated has SELECT on view but deny-all on base → security_invoker blocks
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-00000000c4b1","app_metadata":{"org_id":"00000000-0000-0000-0000-00000000c4a1","role":"AUDITOR"}}';

SELECT throws_ok(
  $$ SELECT 1 FROM public.portal_submissions_unified LIMIT 1 $$,
  '42501',
  NULL,
  'authenticated cannot read unified view over deny-all base tables (security_invoker)'
);

RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
