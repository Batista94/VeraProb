BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(8);

-- ── Seeds ────────────────────────────────────────────────────────────────────
INSERT INTO public.organizations (
  id, name, legal_name, cnpj, timezone, currency_code,
  plan_type, max_vehicles, max_active_contracts, tool_cost_cents,
  dwell_time_seconds, billing_day, contact_email, external_id,
  organization_type, allowed_domains,
  dual_control_threshold_cents
) VALUES
  ('00000000-0000-0000-0000-0000000002a1', 'Org Lock', 'Org Lock SA', '00000000000201',
   'America/Sao_Paulo', 'BRL', 'enterprise', 1000, 50, 15000, 300, 15,
   'lock@test.com', 'EXT_LCK_A', 'LOGISTICS', ARRAY['lock.com'],
   99999999)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.contract_rule_sets (id, organization_id, contract_id)
VALUES ('00000000-0000-0000-0000-0000000002c1',
        '00000000-0000-0000-0000-0000000002a1',
        '00000000-0000-0000-0000-0000000002aa')
ON CONFLICT DO NOTHING;

INSERT INTO public.contract_rule_versions
  (id, rule_set_id, rule_type, rule_config, rule_version, evaluation_order,
   active_from_utc, active_to_utc, created_at_utc)
VALUES
  ('00000000-0000-0000-0000-0000000002d1',
   '00000000-0000-0000-0000-0000000002c1',
   'MAX_TOLERANCE_DELAY', '{"threshold_minutes": 30}'::jsonb, 1, 0,
   '2026-01-01T00:00:00Z', NULL, '2026-01-01T00:00:00Z')
ON CONFLICT DO NOTHING;

INSERT INTO public.sanction_review_queue
  (id, organization_id, ledger_entry_id, set_id, contract_id, verdict_evidence, status)
VALUES
  ('00000000-0000-0000-0000-0000000002e1', '00000000-0000-0000-0000-0000000002a1',
   '00000000-0000-0000-0000-0000000002f1', 'set-lock-1',
   '00000000-0000-0000-0000-0000000002aa', '{}'::jsonb, 'disputed'),
  ('00000000-0000-0000-0000-0000000002e2', '00000000-0000-0000-0000-0000000002a1',
   '00000000-0000-0000-0000-0000000002f2', 'set-lock-2',
   '00000000-0000-0000-0000-0000000002aa', '{}'::jsonb, 'pending'),
  ('00000000-0000-0000-0000-0000000002e3', '00000000-0000-0000-0000-0000000002a1',
   '00000000-0000-0000-0000-0000000002f3', 'set-lock-3',
   '00000000-0000-0000-0000-0000000002aa', '{}'::jsonb, 'pending');

-- ── 1. Static Validation of the NOWAIT lock on resolve_dispute ──────────────
SELECT ok(
  (SELECT pg_get_functiondef(p.oid) ~* 'FOR UPDATE NOWAIT'
     FROM pg_proc p
    WHERE p.proname = 'resolve_dispute'
      AND pg_get_function_arguments(p.oid) ~* 'p_reason_code'),
  'T1: resolve_dispute definition contains FOR UPDATE NOWAIT'
);

-- ── 2. Static Validation of the NOWAIT lock on approve_sanction ──────────────
SELECT ok(
  (SELECT pg_get_functiondef(p.oid) ~* 'FOR UPDATE NOWAIT'
     FROM pg_proc p
    WHERE p.proname = 'approve_sanction'
      AND pg_get_function_arguments(p.oid) ~* 'p_reason_code'),
  'T2: approve_sanction definition contains FOR UPDATE NOWAIT'
);

-- ── 3. Static Validation of the NOWAIT lock on reject_sanction ───────────────
SELECT ok(
  (SELECT pg_get_functiondef(p.oid) ~* 'FOR UPDATE NOWAIT'
     FROM pg_proc p
    WHERE p.proname = 'reject_sanction'
      AND pg_get_function_arguments(p.oid) ~* 'p_reason_code'),
  'T3: reject_sanction definition contains FOR UPDATE NOWAIT'
);

-- ── 4. Verify Happy Path Execution Under RLS ─────────────────────────────────
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-0000000002b1","organization_id":"00000000-0000-0000-0000-0000000002a1","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000002a1","role":"AUDITOR"}}';

-- 4.1 resolve_dispute runs normally when row is not locked by another session
SELECT lives_ok(
  $$ SELECT public.resolve_dispute(
       '00000000-0000-0000-0000-0000000002a1',
       '00000000-0000-0000-0000-0000000002e1',
       'DISPUTE_ACCEPTED',
       'Legitimate proof provided',
       '00000000-0000-0000-0000-0000000002b1', 'auditor@test.com',
       '2026-06-24T11:00:00Z', 'idem-lock-1', 'FORCE_MAJEURE'
     ) $$,
  'T4: resolve_dispute executes successfully on unlocked row'
);

-- 4.2 approve_sanction runs normally when row is not locked by another session
SELECT lives_ok(
  $$ SELECT public.approve_sanction(
       '00000000-0000-0000-0000-0000000002a1',
       '00000000-0000-0000-0000-0000000002e2',
       '00000000-0000-0000-0000-0000000002b1', 'auditor@test.com',
       '2026-06-24T11:00:00Z', 'FORCE_MAJEURE', 'Approved after validation'
     ) $$,
  'T5: approve_sanction executes successfully on unlocked row'
);

-- 4.3 reject_sanction runs normally when row is not locked by another session
SELECT lives_ok(
  $$ SELECT public.reject_sanction(
       '00000000-0000-0000-0000-0000000002a1',
       '00000000-0000-0000-0000-0000000002e3',
       '00000000-0000-0000-0000-0000000002b1', 'auditor@test.com',
       'Justification rejected', 'FORCE_MAJEURE',
       '2026-06-24T11:00:00Z'
     ) $$,
  'T6: reject_sanction executes successfully on unlocked row'
);

-- Verify status changed appropriately
SELECT is(
  (SELECT status FROM public.sanction_review_queue WHERE id = '00000000-0000-0000-0000-0000000002e1'),
  'rejected',
  'T7: resolve_dispute transitioned status to rejected'
);

SELECT is(
  (SELECT status FROM public.sanction_review_queue WHERE id = '00000000-0000-0000-0000-0000000002e2'),
  'applied',
  'T8: approve_sanction transitioned status to applied'
);

SELECT * FROM finish();
ROLLBACK;
