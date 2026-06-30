-- pgTAP: JWT claim path regression — resolve_dispute / reject_sanction / approve_sanction
-- Verifies that all three dispute RPCs use auth.jwt() -> 'app_metadata' ->> 'org_id'
-- (canonical path) and NOT the legacy top-level auth.jwt() ->> 'organization_id'.
-- Critical regression introduced by 20260901000006, fixed by 20260903000003.
-- The happy-path JWTs in this test deliberately omit the top-level organization_id
-- field to surface the regression if it reappears.
-- Run via: make test-db

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(15);

-- ── Seeds ─────────────────────────────────────────────────────────────────────
INSERT INTO public.organizations (
  id, name, legal_name, cnpj, timezone, currency_code,
  plan_type, max_vehicles, max_active_contracts, tool_cost_cents,
  dwell_time_seconds, billing_day, contact_email, external_id,
  organization_type, allowed_domains
) VALUES
  ('00000000-0000-0000-0000-000000000030', 'JWT Reg Org A', 'JWT Reg A SA', '00000000003001',
   'America/Sao_Paulo', 'BRL', 'enterprise', 1000, 50, 15000, 300, 15,
   'a@jwttest.com', 'EXT_JWT_A', 'LOGISTICS', ARRAY['jwttest.com']),
  ('00000000-0000-0000-0000-000000000031', 'JWT Reg Org B', 'JWT Reg B SA', '00000000003101',
   'America/Sao_Paulo', 'BRL', 'enterprise', 1000, 50, 15000, 300, 15,
   'b@jwttest.com', 'EXT_JWT_B', 'LOGISTICS', ARRAY['jwttest.com'])
ON CONFLICT (id) DO NOTHING;

-- Queue entries: disputed (for resolve_dispute) and pending (for approve/reject)
INSERT INTO public.sanction_review_queue
  (id, organization_id, ledger_entry_id, set_id, contract_id, verdict_evidence, status)
VALUES
  -- e1: resolve_dispute happy path (RETRACTED — no snapshot deps)
  ('00000000-0000-0000-0000-0000000031e1', '00000000-0000-0000-0000-000000000030',
   '00000000-0000-0000-0000-0000000031f1', 'set-retract',
   '00000000-0000-0000-0000-0000000030aa', '{}'::jsonb, 'disputed'),
  -- e2: resolve_dispute wrong-org
  ('00000000-0000-0000-0000-0000000031e2', '00000000-0000-0000-0000-000000000030',
   '00000000-0000-0000-0000-0000000031f2', 'set-cross-resolve',
   '00000000-0000-0000-0000-0000000030aa', '{}'::jsonb, 'disputed'),
  -- e3: resolve_dispute NULL app_metadata.org_id
  ('00000000-0000-0000-0000-0000000031e3', '00000000-0000-0000-0000-000000000030',
   '00000000-0000-0000-0000-0000000031f3', 'set-null-resolve',
   '00000000-0000-0000-0000-0000000030aa', '{}'::jsonb, 'disputed'),
  -- e4: reject_sanction happy path
  ('00000000-0000-0000-0000-0000000031e4', '00000000-0000-0000-0000-000000000030',
   '00000000-0000-0000-0000-0000000031f4', 'set-reject',
   '00000000-0000-0000-0000-0000000030aa', '{}'::jsonb, 'pending'),
  -- e5: reject_sanction wrong-org
  ('00000000-0000-0000-0000-0000000031e5', '00000000-0000-0000-0000-000000000030',
   '00000000-0000-0000-0000-0000000031f5', 'set-cross-reject',
   '00000000-0000-0000-0000-0000000030aa', '{}'::jsonb, 'pending'),
  -- e6: approve_sanction happy path
  ('00000000-0000-0000-0000-0000000031e6', '00000000-0000-0000-0000-000000000030',
   '00000000-0000-0000-0000-0000000031f6', 'set-approve',
   '00000000-0000-0000-0000-0000000030aa', '{}'::jsonb, 'pending'),
  -- e7: approve_sanction wrong-org
  ('00000000-0000-0000-0000-0000000031e7', '00000000-0000-0000-0000-000000000030',
   '00000000-0000-0000-0000-0000000031f7', 'set-cross-approve',
   '00000000-0000-0000-0000-0000000030aa', '{}'::jsonb, 'pending'),
  -- e8: reject_sanction NULL app_metadata.org_id
  ('00000000-0000-0000-0000-0000000031e8', '00000000-0000-0000-0000-000000000030',
   '00000000-0000-0000-0000-0000000031f8', 'set-null-reject',
   '00000000-0000-0000-0000-0000000030aa', '{}'::jsonb, 'pending'),
  -- e9: approve_sanction NULL app_metadata.org_id
  ('00000000-0000-0000-0000-0000000031e9', '00000000-0000-0000-0000-000000000030',
   '00000000-0000-0000-0000-0000000031f9', 'set-null-approve',
   '00000000-0000-0000-0000-0000000030aa', '{}'::jsonb, 'pending');

-- Rule set required by approve/reject terminal path (_persist_evidence_snapshot).
INSERT INTO public.contract_rule_sets (id, organization_id, contract_id)
VALUES ('00000000-0000-0000-0000-0000000030bb',
        '00000000-0000-0000-0000-000000000030',
        '00000000-0000-0000-0000-0000000030aa')
ON CONFLICT DO NOTHING;

INSERT INTO public.contract_rule_versions
  (id, rule_set_id, rule_type, rule_config, rule_version, evaluation_order,
   active_from_utc, active_to_utc, created_at_utc)
VALUES ('00000000-0000-0000-0000-0000000030cc',
        '00000000-0000-0000-0000-0000000030bb',
        'MAX_TOLERANCE_DELAY', '{"threshold_minutes": 30}'::jsonb, 1, 0,
        '2026-01-01T00:00:00Z', NULL, '2026-01-01T00:00:00Z')
ON CONFLICT DO NOTHING;

-- 1. resolve_dispute has the correct signature.
SELECT has_function(
  'public', 'resolve_dispute',
  ARRAY['uuid', 'uuid', 'text', 'text', 'uuid', 'text',
        'timestamp with time zone', 'text', 'text'],
  'TC1: resolve_dispute exists with the expected signature'
);

-- 2. resolve_dispute is SECURITY DEFINER.
SELECT is(
  (SELECT prosecdef FROM pg_proc WHERE proname = 'resolve_dispute'),
  true,
  'TC2: resolve_dispute is SECURITY DEFINER'
);

-- ── Authenticated AUDITOR (Org A) — JWT with ONLY app_metadata.org_id ────────
-- Critical regression test: top-level organization_id is deliberately absent.
-- Old (broken) code: auth.jwt() ->> 'organization_id' = NULL -> 42501 for every user.
-- Fixed code: auth.jwt() -> 'app_metadata' ->> 'org_id' = '...030' -> passes.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-000000000039","app_metadata":{"org_id":"00000000-0000-0000-0000-000000000030","role":"AUDITOR"}}';

-- 3. resolve_dispute happy path — ONLY app_metadata.org_id in JWT (regression smoke).
SELECT lives_ok(
  $$ SELECT public.resolve_dispute(
       '00000000-0000-0000-0000-000000000030',
       '00000000-0000-0000-0000-0000000031e1',
       'DISPUTE_RETRACTED', 'Retracted by auditor after re-evaluation.',
       '00000000-0000-0000-0000-000000000039', 'auditor@jwttest.com',
       '2026-09-03T10:00:00Z', '00000000-0000-0000-0000-0000000031e1:RETRACT:001',
       NULL
     ) $$,
  'TC3: resolve_dispute succeeds with ONLY app_metadata.org_id JWT (regression fixed)'
);

-- 4. Idempotency: second call on now-pending row raises P0001.
SELECT throws_ok(
  $$ SELECT public.resolve_dispute(
       '00000000-0000-0000-0000-000000000030',
       '00000000-0000-0000-0000-0000000031e1',
       'DISPUTE_RETRACTED', 'Retracted again.',
       '00000000-0000-0000-0000-000000000039', 'auditor@jwttest.com',
       '2026-09-03T10:05:00Z', '00000000-0000-0000-0000-0000000031e1:RETRACT:002',
       NULL
     ) $$,
  'P0001',
  NULL,
  'TC4: second resolve on non-disputed row raises P0001 (idempotency)'
);

-- 5. reject_sanction happy path — ONLY app_metadata.org_id in JWT.
SELECT lives_ok(
  $$ SELECT public.reject_sanction(
       '00000000-0000-0000-0000-000000000030',
       '00000000-0000-0000-0000-0000000031e4',
       '00000000-0000-0000-0000-000000000039', 'auditor@jwttest.com',
       'GPS evidence inconclusive.', 'FORCE_MAJEURE',
       '2026-09-03T10:10:00Z'
     ) $$,
  'TC5: reject_sanction succeeds with ONLY app_metadata.org_id JWT (regression fixed)'
);

-- 6. approve_sanction happy path — ONLY app_metadata.org_id in JWT.
SELECT lives_ok(
  $$ SELECT public.approve_sanction(
       '00000000-0000-0000-0000-000000000030',
       '00000000-0000-0000-0000-0000000031e6',
       '00000000-0000-0000-0000-000000000039', 'auditor@jwttest.com',
       '2026-09-03T10:20:00Z'
     ) $$,
  'TC6: approve_sanction succeeds with ONLY app_metadata.org_id JWT (regression fixed)'
);

-- ── Cross-tenant: JWT org_id = Org B, p_organization_id = Org A ───────────────
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-000000000039","app_metadata":{"org_id":"00000000-0000-0000-0000-000000000031","role":"AUDITOR"}}';

-- 7. resolve_dispute wrong-org → 42501 (anti-oracle, INV-26).
SELECT throws_ok(
  $$ SELECT public.resolve_dispute(
       '00000000-0000-0000-0000-000000000030',
       '00000000-0000-0000-0000-0000000031e2',
       'DISPUTE_RETRACTED', 'cross-tenant attempt',
       '00000000-0000-0000-0000-000000000039', 'evil@jwttest.com',
       '2026-09-03T10:30:00Z', '00000000-0000-0000-0000-0000000031e2:RETRACT:001',
       NULL
     ) $$,
  '42501',
  NULL,
  'TC7: resolve_dispute cross-tenant JWT -> 42501 (INV-22, INV-26)'
);

-- 8. reject_sanction wrong-org → 42501.
SELECT throws_ok(
  $$ SELECT public.reject_sanction(
       '00000000-0000-0000-0000-000000000030',
       '00000000-0000-0000-0000-0000000031e5',
       '00000000-0000-0000-0000-000000000039', 'evil@jwttest.com',
       'cross-tenant', 'FORCE_MAJEURE',
       '2026-09-03T10:35:00Z'
     ) $$,
  '42501',
  NULL,
  'TC8: reject_sanction cross-tenant JWT -> 42501 (INV-22, INV-26)'
);

-- 9. approve_sanction wrong-org → 42501.
SELECT throws_ok(
  $$ SELECT public.approve_sanction(
       '00000000-0000-0000-0000-000000000030',
       '00000000-0000-0000-0000-0000000031e7',
       '00000000-0000-0000-0000-000000000039', 'evil@jwttest.com',
       '2026-09-03T10:40:00Z'
     ) $$,
  '42501',
  NULL,
  'TC9: approve_sanction cross-tenant JWT -> 42501 (INV-22, INV-26)'
);

-- ── NULL app_metadata.org_id: fail-closed (INV-2) ─────────────────────────────
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-000000000039","app_metadata":{"role":"AUDITOR"}}';

-- 10. resolve_dispute NULL app_metadata.org_id → 42501.
SELECT throws_ok(
  $$ SELECT public.resolve_dispute(
       '00000000-0000-0000-0000-000000000030',
       '00000000-0000-0000-0000-0000000031e3',
       'DISPUTE_RETRACTED', 'null org attempt',
       '00000000-0000-0000-0000-000000000039', 'evil@jwttest.com',
       '2026-09-03T10:45:00Z', '00000000-0000-0000-0000-0000000031e3:RETRACT:001',
       NULL
     ) $$,
  '42501',
  NULL,
  'TC10: resolve_dispute NULL app_metadata.org_id -> 42501 (fail-closed, INV-2)'
);

-- 11. reject_sanction NULL app_metadata.org_id → 42501.
SELECT throws_ok(
  $$ SELECT public.reject_sanction(
       '00000000-0000-0000-0000-000000000030',
       '00000000-0000-0000-0000-0000000031e8',
       '00000000-0000-0000-0000-000000000039', 'evil@jwttest.com',
       'null org attempt', 'FORCE_MAJEURE',
       '2026-09-03T10:50:00Z'
     ) $$,
  '42501',
  NULL,
  'TC11: reject_sanction NULL app_metadata.org_id -> 42501 (fail-closed, INV-2)'
);

-- 12. approve_sanction NULL app_metadata.org_id → 42501.
SELECT throws_ok(
  $$ SELECT public.approve_sanction(
       '00000000-0000-0000-0000-000000000030',
       '00000000-0000-0000-0000-0000000031e9',
       '00000000-0000-0000-0000-000000000039', 'evil@jwttest.com',
       '2026-09-03T10:55:00Z'
     ) $$,
  '42501',
  NULL,
  'TC12: approve_sanction NULL app_metadata.org_id -> 42501 (fail-closed, INV-2)'
);

RESET ROLE;

-- ── Grant hardening assertions ─────────────────────────────────────────────────
-- 13. service_role may NOT execute resolve_dispute (no Data-API bypass path).
SELECT ok(
  NOT has_function_privilege('service_role',
    'public.resolve_dispute(uuid, uuid, text, text, uuid, text, timestamp with time zone, text, text)',
    'EXECUTE'),
  'TC13: service_role may NOT execute resolve_dispute'
);

-- 14. service_role may NOT execute reject_sanction.
SELECT ok(
  NOT has_function_privilege('service_role',
    'public.reject_sanction(uuid, uuid, uuid, text, text, text, timestamp with time zone)',
    'EXECUTE'),
  'TC14: service_role may NOT execute reject_sanction'
);

-- 15. service_role may NOT execute approve_sanction.
SELECT ok(
  NOT has_function_privilege('service_role',
    'public.approve_sanction(uuid, uuid, uuid, text, timestamp with time zone, text, text)',
    'EXECUTE'),
  'TC15: service_role may NOT execute approve_sanction'
);

SELECT * FROM finish();
ROLLBACK;
