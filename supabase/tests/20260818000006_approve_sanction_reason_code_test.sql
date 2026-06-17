BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(16);

-- ── Seeds ────────────────────────────────────────────────────────────────────
INSERT INTO public.organizations (
  id, name, legal_name, cnpj, timezone, currency_code,
  plan_type, max_vehicles, max_active_contracts, tool_cost_cents,
  dwell_time_seconds, billing_day, contact_email, external_id,
  organization_type, allowed_domains
) VALUES
  ('00000000-0000-0000-0000-0000000009a1', 'Org RC', 'Org RC SA', '00000000000901',
   'America/Sao_Paulo', 'BRL', 'enterprise', 1000, 50, 15000, 300, 15,
   'rc@test.com', 'EXT_RC', 'LOGISTICS', ARRAY['test.com'])
ON CONFLICT (id) DO NOTHING;

-- Global taxonomy code used by the happy / injection paths.
INSERT INTO public.dispute_reason_codes
  (code, category, label_pt, label_en, is_active, organization_id)
VALUES ('TEST_APPROVE_RC', 'TECHNICAL', 'Teste', 'Test', TRUE, NULL)
ON CONFLICT (code) DO NOTHING;

INSERT INTO public.sanction_review_queue
  (id, organization_id, ledger_entry_id, set_id, contract_id, verdict_evidence, status)
VALUES
  ('00000000-0000-0000-0000-0000000009e1', '00000000-0000-0000-0000-0000000009a1',
   '00000000-0000-0000-0000-0000000009f1', 'set-rc-code',
   '00000000-0000-0000-0000-0000000009aa', '{}'::jsonb, 'pending'),
  ('00000000-0000-0000-0000-0000000009e2', '00000000-0000-0000-0000-0000000009a1',
   '00000000-0000-0000-0000-0000000009f2', 'set-rc-null',
   '00000000-0000-0000-0000-0000000009aa', '{}'::jsonb, 'pending'),
  ('00000000-0000-0000-0000-0000000009e3', '00000000-0000-0000-0000-0000000009a1',
   '00000000-0000-0000-0000-0000000009f3', 'set-rc-bad',
   '00000000-0000-0000-0000-0000000009aa', '{}'::jsonb, 'pending'),
  ('00000000-0000-0000-0000-0000000009e4', '00000000-0000-0000-0000-0000000009a1',
   '00000000-0000-0000-0000-0000000009f4', 'set-rc-sqli',
   '00000000-0000-0000-0000-0000000009aa', '{}'::jsonb, 'pending');

-- Rule set required by approve_sanction terminal path (_persist_evidence_snapshot).
INSERT INTO public.contract_rule_sets (id, organization_id, contract_id)
VALUES ('00000000-0000-0000-0000-0000000009b1',
        '00000000-0000-0000-0000-0000000009a1',
        '00000000-0000-0000-0000-0000000009aa')
ON CONFLICT DO NOTHING;

INSERT INTO public.contract_rule_versions
  (id, rule_set_id, rule_type, rule_config, rule_version, evaluation_order,
   active_from_utc, active_to_utc, created_at_utc)
VALUES ('00000000-0000-0000-0000-0000000009b2',
        '00000000-0000-0000-0000-0000000009b1',
        'MAX_TOLERANCE_DELAY', '{"threshold_minutes": 30}'::jsonb, 1, 0,
        '2026-01-01T00:00:00Z', NULL, '2026-01-01T00:00:00Z')
ON CONFLICT DO NOTHING;

-- 1. approve_sanction exists with the NEW 7-arg signature.
SELECT has_function(
  'public', 'approve_sanction',
  ARRAY['uuid', 'uuid', 'uuid', 'text', 'timestamp with time zone', 'text', 'text'],
  'approve_sanction exists with the 7-arg signature (reason code + note)'
);

-- 2. approve_sanction is SECURITY DEFINER.
SELECT is(
  (SELECT prosecdef FROM pg_proc WHERE proname = 'approve_sanction'),
  true,
  'approve_sanction is SECURITY DEFINER'
);

-- 3. Exactly ONE approve_sanction overload exists (old 5-arg dropped).
SELECT is(
  (SELECT count(*)::int FROM pg_proc WHERE proname = 'approve_sanction'),
  1,
  'old 5-arg approve_sanction overload no longer exists (single overload)'
);

-- 4. authenticated may execute the 7-arg overload.
SELECT ok(
  has_function_privilege('authenticated',
    'public.approve_sanction(uuid, uuid, uuid, text, timestamp with time zone, text, text)',
    'EXECUTE'),
  'authenticated may execute approve_sanction'
);

-- 5. anon may NOT execute.
SELECT ok(
  NOT has_function_privilege('anon',
    'public.approve_sanction(uuid, uuid, uuid, text, timestamp with time zone, text, text)',
    'EXECUTE'),
  'anon may NOT execute approve_sanction'
);

-- 6. service_role may NOT execute (no Data-API bypass).
SELECT ok(
  NOT has_function_privilege('service_role',
    'public.approve_sanction(uuid, uuid, uuid, text, timestamp with time zone, text, text)',
    'EXECUTE'),
  'service_role may NOT execute approve_sanction'
);

-- ── Authenticated AUDITOR (Org RC) ─────────────────────────────────────────────
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-0000000009b9","organization_id":"00000000-0000-0000-0000-0000000009a1","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000009a1","role":"AUDITOR"}}';

-- 7. Happy path: seal WITH a valid reason code + note.
SELECT lives_ok(
  $$ SELECT public.approve_sanction(
       '00000000-0000-0000-0000-0000000009a1',
       '00000000-0000-0000-0000-0000000009e1',
       '00000000-0000-0000-0000-0000000009b9', 'auditor@test.com',
       '2026-08-18T12:00:00Z',
       'TEST_APPROVE_RC',
       'Laudo técnico anexado confirma a infração.'
     ) $$,
  'approve_sanction seals with a valid reason code + note'
);

-- 8. Queue flipped to applied.
SELECT is(
  (SELECT status FROM public.sanction_review_queue
    WHERE id = '00000000-0000-0000-0000-0000000009e1'),
  'applied',
  'approve flips the queue status to applied'
);

-- 9. Ledger payload carries the supplied reason_code (INV-21/23).
SELECT is(
  (SELECT payload->>'reason_code' FROM public.sla_audit_ledger_v2
    WHERE type = 'VERDICT_SEALED'
      AND payload->>'queue_entry_id' = '00000000-0000-0000-0000-0000000009e1'),
  'TEST_APPROVE_RC',
  'VERDICT_SEALED payload records the reviewer reason code'
);

-- 10. Ledger payload carries the raw reviewer_reason note.
SELECT is(
  (SELECT payload->>'reviewer_reason' FROM public.sla_audit_ledger_v2
    WHERE type = 'VERDICT_SEALED'
      AND payload->>'queue_entry_id' = '00000000-0000-0000-0000-0000000009e1'),
  'Laudo técnico anexado confirma a infração.',
  'VERDICT_SEALED payload records the raw reviewer note'
);

-- 11. Back-compat: 5-arg-style call (no code/note) still seals.
SELECT lives_ok(
  $$ SELECT public.approve_sanction(
       '00000000-0000-0000-0000-0000000009a1',
       '00000000-0000-0000-0000-0000000009e2',
       '00000000-0000-0000-0000-0000000009b9', 'auditor@test.com',
       '2026-08-18T12:01:00Z'
     ) $$,
  'approve_sanction still seals when called with the legacy 5 args'
);

-- 12. With no code supplied the payload reason_code is NULL (not empty string).
SELECT ok(
  (SELECT payload->>'reason_code' IS NULL FROM public.sla_audit_ledger_v2
    WHERE type = 'VERDICT_SEALED'
      AND payload->>'queue_entry_id' = '00000000-0000-0000-0000-0000000009e2'),
  'legacy seal records a NULL reason_code'
);

-- 13. Unknown/inactive reason code → opaque insufficient_privilege (anti-oracle).
SELECT throws_ok(
  $$ SELECT public.approve_sanction(
       '00000000-0000-0000-0000-0000000009a1',
       '00000000-0000-0000-0000-0000000009e3',
       '00000000-0000-0000-0000-0000000009b9', 'auditor@test.com',
       '2026-08-18T12:02:00Z',
       'NONEXISTENT_CODE_ZZZ'
     ) $$,
  '42501',
  'Sanction approval rejected.',
  'unknown reason code fails opaque (insufficient_privilege)'
);

-- 14. The rejected entry was NOT sealed (still pending).
SELECT is(
  (SELECT status FROM public.sanction_review_queue
    WHERE id = '00000000-0000-0000-0000-0000000009e3'),
  'pending',
  'a rejected (bad-code) approval leaves the entry pending'
);

-- 15. SQL-injection text in the note is stored as a literal (parametrised path).
SELECT lives_ok(
  $$ SELECT public.approve_sanction(
       '00000000-0000-0000-0000-0000000009a1',
       '00000000-0000-0000-0000-0000000009e4',
       '00000000-0000-0000-0000-0000000009b9', 'auditor@test.com',
       '2026-08-18T12:03:00Z',
       'TEST_APPROVE_RC',
       '''; DROP TABLE public.sanction_review_queue; --'
     ) $$,
  'SQLi note is bound as a literal — no DDL executes'
);

-- 16. The injection note is stored verbatim AND the table survived.
SELECT is(
  (SELECT payload->>'reviewer_reason' FROM public.sla_audit_ledger_v2
    WHERE type = 'VERDICT_SEALED'
      AND payload->>'queue_entry_id' = '00000000-0000-0000-0000-0000000009e4'),
  '''; DROP TABLE public.sanction_review_queue; --',
  'SQLi text persisted verbatim (table intact, literal stored)'
);

SELECT * FROM finish();
ROLLBACK;
