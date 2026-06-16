BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(21);

-- ── Seeds ────────────────────────────────────────────────────────────────────
-- Org A (full column set to satisfy NOT NULLs).
INSERT INTO public.organizations (
  id, name, legal_name, cnpj, timezone, currency_code,
  plan_type, max_vehicles, max_active_contracts, tool_cost_cents,
  dwell_time_seconds, billing_day, contact_email, external_id,
  organization_type, allowed_domains
) VALUES
  ('00000000-0000-0000-0000-0000000008a1', 'Org A', 'Org A SA', '00000000000801',
   'America/Sao_Paulo', 'BRL', 'enterprise', 1000, 50, 15000, 300, 15,
   'a@test.com', 'EXT_AR_A', 'LOGISTICS', ARRAY['test.com'])
ON CONFLICT (id) DO NOTHING;

-- Six pending queue entries (one per scenario).
INSERT INTO public.sanction_review_queue
  (id, organization_id, ledger_entry_id, set_id, contract_id, verdict_evidence, status)
VALUES
  ('00000000-0000-0000-0000-0000000008e1', '00000000-0000-0000-0000-0000000008a1',
   '00000000-0000-0000-0000-0000000008f1', 'set-approve',
   '00000000-0000-0000-0000-0000000008aa', '{}'::jsonb, 'pending'),
  ('00000000-0000-0000-0000-0000000008e2', '00000000-0000-0000-0000-0000000008a1',
   '00000000-0000-0000-0000-0000000008f2', 'set-reject',
   '00000000-0000-0000-0000-0000000008aa', '{}'::jsonb, 'pending'),
  ('00000000-0000-0000-0000-0000000008e3', '00000000-0000-0000-0000-0000000008a1',
   '00000000-0000-0000-0000-0000000008f3', 'set-emptyreason',
   '00000000-0000-0000-0000-0000000008aa', '{}'::jsonb, 'pending'),
  ('00000000-0000-0000-0000-0000000008e4', '00000000-0000-0000-0000-0000000008a1',
   '00000000-0000-0000-0000-0000000008f4', 'set-spoof',
   '00000000-0000-0000-0000-0000000008aa', '{}'::jsonb, 'pending'),
  ('00000000-0000-0000-0000-0000000008e5', '00000000-0000-0000-0000-0000000008a1',
   '00000000-0000-0000-0000-0000000008f5', 'set-cross',
   '00000000-0000-0000-0000-0000000008aa', '{}'::jsonb, 'pending'),
  ('00000000-0000-0000-0000-0000000008e6', '00000000-0000-0000-0000-0000000008a1',
   '00000000-0000-0000-0000-0000000008f6', 'set-role',
   '00000000-0000-0000-0000-0000000008aa', '{}'::jsonb, 'pending');

-- 1. approve_sanction exists with the expected signature.
SELECT has_function(
  'public', 'approve_sanction',
  ARRAY['uuid', 'uuid', 'uuid', 'text', 'timestamp with time zone', 'text', 'text'],
  'approve_sanction exists with the expected signature'
);

-- 2. approve_sanction is SECURITY DEFINER.
SELECT is(
  (SELECT prosecdef FROM pg_proc WHERE proname = 'approve_sanction'),
  true,
  'approve_sanction is SECURITY DEFINER'
);

-- 3. reject_sanction exists with the expected signature.
SELECT has_function(
  'public', 'reject_sanction',
  ARRAY['uuid', 'uuid', 'uuid', 'text', 'text', 'text', 'timestamp with time zone'],
  'reject_sanction exists with the expected signature'
);

-- 4. reject_sanction is SECURITY DEFINER.
SELECT is(
  (SELECT prosecdef FROM pg_proc WHERE proname = 'reject_sanction'),
  true,
  'reject_sanction is SECURITY DEFINER'
);

-- 5. authenticated may execute approve.
SELECT ok(
  has_function_privilege('authenticated',
    'public.approve_sanction(uuid, uuid, uuid, text, timestamp with time zone, text, text)',
    'EXECUTE'),
  'authenticated may execute approve_sanction'
);

-- 6. anon may NOT execute approve (Max hardening).
SELECT ok(
  NOT has_function_privilege('anon',
    'public.approve_sanction(uuid, uuid, uuid, text, timestamp with time zone, text, text)',
    'EXECUTE'),
  'anon may NOT execute approve_sanction'
);

-- 7. service_role may NOT execute approve (no Data-API bypass path).
SELECT ok(
  NOT has_function_privilege('service_role',
    'public.approve_sanction(uuid, uuid, uuid, text, timestamp with time zone, text, text)',
    'EXECUTE'),
  'service_role may NOT execute approve_sanction'
);

-- 8. authenticated may execute reject.
SELECT ok(
  has_function_privilege('authenticated',
    'public.reject_sanction(uuid, uuid, uuid, text, text, text, timestamp with time zone)',
    'EXECUTE'),
  'authenticated may execute reject_sanction'
);

-- 9. anon may NOT execute reject.
SELECT ok(
  NOT has_function_privilege('anon',
    'public.reject_sanction(uuid, uuid, uuid, text, text, text, timestamp with time zone)',
    'EXECUTE'),
  'anon may NOT execute reject_sanction'
);

-- 10. service_role may NOT execute reject.
SELECT ok(
  NOT has_function_privilege('service_role',
    'public.reject_sanction(uuid, uuid, uuid, text, text, text, timestamp with time zone)',
    'EXECUTE'),
  'service_role may NOT execute reject_sanction'
);

-- ── Authenticated AUDITOR (Org A) ──────────────────────────────────────────────
-- The reviewer is bound to the JWT `sub`; both legacy top-level organization_id
-- (queue RLS SELECT) and canonical app_metadata.org_id (RPC guard) are set.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-0000000008b9","organization_id":"00000000-0000-0000-0000-0000000008a1","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000008a1","role":"AUDITOR"}}';

-- 11. Happy path (approve): pending → applied.
SELECT lives_ok(
  $$ SELECT public.approve_sanction(
       '00000000-0000-0000-0000-0000000008a1',
       '00000000-0000-0000-0000-0000000008e1',
       '00000000-0000-0000-0000-0000000008b9', 'auditor@test.com',
       '2026-08-12T12:00:00Z'
     ) $$,
  'approve_sanction executes for an authenticated auditor'
);

-- 12. Queue status flipped to applied.
SELECT is(
  (SELECT status FROM public.sanction_review_queue
    WHERE id = '00000000-0000-0000-0000-0000000008e1'),
  'applied',
  'approve flips the queue status to applied'
);

-- 13. Exactly one VERDICT_SEALED fact for the queue entry (INV-3).
SELECT is(
  (SELECT count(*)::int FROM public.sla_audit_ledger_v2
    WHERE organization_id = '00000000-0000-0000-0000-0000000008a1'
      AND type = 'VERDICT_SEALED'
      AND payload->>'queue_entry_id' = '00000000-0000-0000-0000-0000000008e1'),
  1,
  'approve appends exactly one VERDICT_SEALED fact'
);

-- 14. Idempotency: a second approve on the now-applied row loses (P0001).
SELECT throws_ok(
  $$ SELECT public.approve_sanction(
       '00000000-0000-0000-0000-0000000008a1',
       '00000000-0000-0000-0000-0000000008e1',
       '00000000-0000-0000-0000-0000000008b9', 'auditor@test.com',
       '2026-08-12T12:05:00Z'
     ) $$,
  'P0001',
  NULL,
  'second approve on a non-pending row raises P0001 (idempotency)'
);

-- 15. Happy path (reject): pending → rejected.
SELECT lives_ok(
  $$ SELECT public.reject_sanction(
       '00000000-0000-0000-0000-0000000008a1',
       '00000000-0000-0000-0000-0000000008e2',
       '00000000-0000-0000-0000-0000000008b9', 'auditor@test.com',
       'GPS evidence was inconclusive for this route.', 'FORCE_MAJEURE',
       '2026-08-12T12:10:00Z'
     ) $$,
  'reject_sanction executes for an authenticated auditor'
);

-- 16. Queue status flipped to rejected.
SELECT is(
  (SELECT status FROM public.sanction_review_queue
    WHERE id = '00000000-0000-0000-0000-0000000008e2'),
  'rejected',
  'reject flips the queue status to rejected'
);

-- 17. Exactly one VERDICT_REFUSED fact for the queue entry (INV-3).
SELECT is(
  (SELECT count(*)::int FROM public.sla_audit_ledger_v2
    WHERE organization_id = '00000000-0000-0000-0000-0000000008a1'
      AND type = 'VERDICT_REFUSED'
      AND payload->>'queue_entry_id' = '00000000-0000-0000-0000-0000000008e2'),
  1,
  'reject appends exactly one VERDICT_REFUSED fact'
);

-- 18. Reject with an empty reason_code is rejected (fail-closed, opaque 42501).
-- Post-taxonomy (008): the structured reason_code is the mandatory field; free
-- text is an optional complement, so the gate moved from reason → reason_code.
SELECT throws_ok(
  $$ SELECT public.reject_sanction(
       '00000000-0000-0000-0000-0000000008a1',
       '00000000-0000-0000-0000-0000000008e3',
       '00000000-0000-0000-0000-0000000008b9', 'auditor@test.com',
       '    ', '   ',
       '2026-08-12T12:12:00Z'
     ) $$,
  '42501',
  NULL,
  'reject with an empty reason_code fails closed (42501)'
);

-- 19. Reviewer spoofing: p_reviewed_by_user_id <> JWT sub is rejected (42501).
SELECT throws_ok(
  $$ SELECT public.approve_sanction(
       '00000000-0000-0000-0000-0000000008a1',
       '00000000-0000-0000-0000-0000000008e4',
       '00000000-0000-0000-0000-0000000008c9', 'auditor@test.com',
       '2026-08-12T12:14:00Z'
     ) $$,
  '42501',
  NULL,
  'reviewer id not matching the JWT sub is rejected (anti-spoof, 42501)'
);

-- ── Cross-tenant (Org B JWT) ──────────────────────────────────────────────────
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-0000000008b9","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000008b2","role":"AUDITOR"}}';

-- 20. Wrong-org approve is rejected with 42501 (anti-oracle, INV-26).
SELECT throws_ok(
  $$ SELECT public.approve_sanction(
       '00000000-0000-0000-0000-0000000008a1',
       '00000000-0000-0000-0000-0000000008e5',
       '00000000-0000-0000-0000-0000000008b9', 'evil@test.com',
       '2026-08-12T12:15:00Z'
     ) $$,
  '42501',
  NULL,
  'cross-tenant approve is rejected with 42501'
);

-- ── Wrong role (OPERATOR, Org A) ──────────────────────────────────────────────
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-0000000008b9","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000008a1","role":"OPERATOR"}}';

-- 21. OPERATOR is rejected with 42501 (server-side RBAC).
SELECT throws_ok(
  $$ SELECT public.approve_sanction(
       '00000000-0000-0000-0000-0000000008a1',
       '00000000-0000-0000-0000-0000000008e6',
       '00000000-0000-0000-0000-0000000008b9', 'op@test.com',
       '2026-08-12T12:20:00Z'
     ) $$,
  '42501',
  NULL,
  'OPERATOR role is rejected with 42501'
);

RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
