BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(14);

-- ── Seeds ────────────────────────────────────────────────────────────────────
-- Org A (full column set to satisfy NOT NULLs).
INSERT INTO public.organizations (
  id, name, legal_name, cnpj, timezone, currency_code,
  plan_type, max_vehicles, max_active_contracts, tool_cost_cents,
  dwell_time_seconds, billing_day, contact_email, external_id,
  organization_type, allowed_domains
) VALUES
  ('00000000-0000-0000-0000-0000000009a1', 'Org A', 'Org A SA', '00000000000901',
   'America/Sao_Paulo', 'BRL', 'enterprise', 1000, 50, 15000, 300, 15,
   'a@test.com', 'EXT_RD_A', 'LOGISTICS', ARRAY['test.com'])
ON CONFLICT (id) DO NOTHING;

-- Rule set + active version (overturn arc seals an inline snapshot).
INSERT INTO public.contract_rule_sets (id, organization_id, contract_id)
VALUES ('00000000-0000-0000-0000-0000000009c1',
        '00000000-0000-0000-0000-0000000009a1',
        '00000000-0000-0000-0000-0000000009aa');

INSERT INTO public.contract_rule_versions
  (id, rule_set_id, rule_type, rule_config, rule_version, evaluation_order,
   active_from_utc, active_to_utc)
VALUES
  ('00000000-0000-0000-0000-0000000009d1',
   '00000000-0000-0000-0000-0000000009c1',
   'NO_SHOW_PENALTY', '{"penalty_amount_cents": 50000}'::jsonb, 1, 0,
   '2026-01-01T00:00:00Z', NULL);

-- Four disputed queue entries (one per arc/exploit scenario).
INSERT INTO public.sanction_review_queue
  (id, organization_id, ledger_entry_id, set_id, contract_id, verdict_evidence, status)
VALUES
  ('00000000-0000-0000-0000-0000000009e1', '00000000-0000-0000-0000-0000000009a1',
   '00000000-0000-0000-0000-0000000009f1', 'set-accept',
   '00000000-0000-0000-0000-0000000009aa', '{}'::jsonb, 'disputed'),
  ('00000000-0000-0000-0000-0000000009e2', '00000000-0000-0000-0000-0000000009a1',
   '00000000-0000-0000-0000-0000000009f2', 'set-overturn',
   '00000000-0000-0000-0000-0000000009aa', '{}'::jsonb, 'disputed'),
  ('00000000-0000-0000-0000-0000000009e3', '00000000-0000-0000-0000-0000000009a1',
   '00000000-0000-0000-0000-0000000009f3', 'set-cross',
   '00000000-0000-0000-0000-0000000009aa', '{}'::jsonb, 'disputed'),
  ('00000000-0000-0000-0000-0000000009e4', '00000000-0000-0000-0000-0000000009a1',
   '00000000-0000-0000-0000-0000000009f4', 'set-role',
   '00000000-0000-0000-0000-0000000009aa', '{}'::jsonb, 'disputed');

-- 1. Function exists with the expected signature.
SELECT has_function(
  'public', 'resolve_dispute',
  ARRAY['uuid', 'uuid', 'text', 'text', 'uuid', 'text',
        'timestamp with time zone', 'text'],
  'resolve_dispute exists with the expected signature'
);

-- 2. SECURITY DEFINER.
SELECT is(
  (SELECT prosecdef FROM pg_proc WHERE proname = 'resolve_dispute'),
  true,
  'resolve_dispute is SECURITY DEFINER'
);

-- 3. authenticated may execute.
SELECT ok(
  has_function_privilege('authenticated',
    'public.resolve_dispute(uuid, uuid, text, text, uuid, text, timestamp with time zone, text)',
    'EXECUTE'),
  'authenticated may execute resolve_dispute'
);

-- 4. anon may NOT execute (Max hardening).
SELECT ok(
  NOT has_function_privilege('anon',
    'public.resolve_dispute(uuid, uuid, text, text, uuid, text, timestamp with time zone, text)',
    'EXECUTE'),
  'anon may NOT execute resolve_dispute'
);

-- 5. service_role may NOT execute (Max hardening — no Data-API bypass path).
SELECT ok(
  NOT has_function_privilege('service_role',
    'public.resolve_dispute(uuid, uuid, text, text, uuid, text, timestamp with time zone, text)',
    'EXECUTE'),
  'service_role may NOT execute resolve_dispute'
);

-- ── Authenticated AUDITOR (Org A) ──────────────────────────────────────────────
-- NOTE: the queue RLS SELECT policy (srq_select_own_org) reads the LEGACY
-- top-level `organization_id` claim, while resolve_dispute reads the canonical
-- `app_metadata.org_id`. Both are set so the verification SELECTs (run as
-- authenticated, under RLS) and the RPC guard pass.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","organization_id":"00000000-0000-0000-0000-0000000009a1","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000009a1","role":"AUDITOR"}}';

-- 6. Happy path (accept): disputed → rejected.
SELECT lives_ok(
  $$ SELECT public.resolve_dispute(
       '00000000-0000-0000-0000-0000000009a1',
       '00000000-0000-0000-0000-0000000009e1',
       'DISPUTE_ACCEPTED', 'Contractor proved force majeure.',
       '00000000-0000-0000-0000-0000000009b9', 'auditor@test.com',
       '2026-08-09T12:00:00Z', '00000000-0000-0000-0000-0000000009e1:DISPUTE_ACCEPTED:SNAPSHOT'
     ) $$,
  'resolve_dispute (accept) executes for an authenticated auditor'
);

-- 7. Queue status flipped to rejected.
SELECT is(
  (SELECT status FROM public.sanction_review_queue
    WHERE id = '00000000-0000-0000-0000-0000000009e1'),
  'rejected',
  'accept arc flips the queue status to rejected'
);

-- 8. Exactly one DISPUTE_ACCEPTED fact for the queue entry (INV-3).
SELECT is(
  (SELECT count(*)::int FROM public.sla_audit_ledger_v2
    WHERE organization_id = '00000000-0000-0000-0000-0000000009a1'
      AND type = 'DISPUTE_ACCEPTED'
      AND payload->>'queue_entry_id' = '00000000-0000-0000-0000-0000000009e1'),
  1,
  'accept arc appends exactly one DISPUTE_ACCEPTED resolution fact'
);

-- 9. Idempotency: a second call on the now-rejected row loses (P0001).
SELECT throws_ok(
  $$ SELECT public.resolve_dispute(
       '00000000-0000-0000-0000-0000000009a1',
       '00000000-0000-0000-0000-0000000009e1',
       'DISPUTE_ACCEPTED', 'Contractor proved force majeure.',
       '00000000-0000-0000-0000-0000000009b9', 'auditor@test.com',
       '2026-08-09T12:05:00Z', '00000000-0000-0000-0000-0000000009e1:DISPUTE_ACCEPTED:SNAPSHOT'
     ) $$,
  'P0001',
  NULL,
  'second resolution on a non-disputed row raises P0001 (idempotency)'
);

-- 10. Overturn arc: disputed → applied AND seals a forensic snapshot (INV-21).
SELECT lives_ok(
  $$ SELECT public.resolve_dispute(
       '00000000-0000-0000-0000-0000000009a1',
       '00000000-0000-0000-0000-0000000009e2',
       'DISPUTE_OVERTURNED', 'Evidence reinstated after appeal.',
       '00000000-0000-0000-0000-0000000009b9', 'auditor@test.com',
       '2026-08-09T12:10:00Z', '00000000-0000-0000-0000-0000000009e2:DISPUTE_OVERTURNED:SNAPSHOT'
     ) $$,
  'resolve_dispute (overturn) executes and seals inline'
);

-- 11. Overturn snapshot persisted in the same transaction.
SELECT is(
  (SELECT count(*)::int FROM public.forensic_evidence_snapshots s
     JOIN public.sla_audit_ledger_v2 l ON l.id = s.ledger_entry_id
    WHERE s.organization_id = '00000000-0000-0000-0000-0000000009a1'
      AND l.payload->>'queue_entry_id' = '00000000-0000-0000-0000-0000000009e2'),
  1,
  'overturn arc seals exactly one forensic snapshot linked to the ledger fact'
);

-- ── Cross-tenant (Org B JWT) ──────────────────────────────────────────────────
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000009b2","role":"AUDITOR"}}';

-- 12. Wrong-org resolve is rejected with 42501 (anti-oracle, INV-26).
SELECT throws_ok(
  $$ SELECT public.resolve_dispute(
       '00000000-0000-0000-0000-0000000009a1',
       '00000000-0000-0000-0000-0000000009e3',
       'DISPUTE_ACCEPTED', 'cross tenant attempt here',
       '00000000-0000-0000-0000-0000000009b9', 'evil@test.com',
       '2026-08-09T12:15:00Z', '00000000-0000-0000-0000-0000000009e3:DISPUTE_ACCEPTED:SNAPSHOT'
     ) $$,
  '42501',
  NULL,
  'cross-tenant resolve is rejected with 42501'
);

-- ── Wrong role (OPERATOR, Org A) ──────────────────────────────────────────────
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000009a1","role":"OPERATOR"}}';

-- 13. OPERATOR is rejected with 42501 (server-side RBAC).
SELECT throws_ok(
  $$ SELECT public.resolve_dispute(
       '00000000-0000-0000-0000-0000000009a1',
       '00000000-0000-0000-0000-0000000009e4',
       'DISPUTE_ACCEPTED', 'operator escalation attempt',
       '00000000-0000-0000-0000-0000000009b9', 'op@test.com',
       '2026-08-09T12:20:00Z', '00000000-0000-0000-0000-0000000009e4:DISPUTE_ACCEPTED:SNAPSHOT'
     ) $$,
  '42501',
  NULL,
  'OPERATOR role is rejected with 42501'
);

RESET ROLE;

-- 14. Defense-in-depth: a direct duplicate resolution INSERT raises 23505.
SELECT throws_ok(
  $$ INSERT INTO public.sla_audit_ledger_v2
       (organization_id, type, contract_id, plan_version, occurred_at_utc, payload)
     VALUES
       ('00000000-0000-0000-0000-0000000009a1', 'DISPUTE_ACCEPTED',
        '00000000-0000-0000-0000-0000000009aa', 0, '2026-08-09T12:25:00Z',
        '{"queue_entry_id":"00000000-0000-0000-0000-0000000009e1"}'::jsonb) $$,
  '23505',
  NULL,
  'direct duplicate resolution fact is blocked by the per-partition unique index'
);

SELECT * FROM finish();
ROLLBACK;
