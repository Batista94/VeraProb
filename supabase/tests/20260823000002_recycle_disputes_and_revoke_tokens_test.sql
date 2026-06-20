-- Behavioral coverage for 20260823000002_recycle_disputes_and_revoke_tokens.sql
-- Reproduces the production 23505 (dispute → retract → dispute → resolve) and
-- proves the cycle discriminator fixes it for BOTH terminal arcs:
--   Case 2 (Anular  → DISPUTE_ACCEPTED   → rejected)
--   Case 1 (Confirmar → DISPUTE_OVERTURNED → applied, seals snapshot)
-- Also asserts: dispute_round increments, same-cycle double-seal still 23505
-- (defense-in-depth intact), and the portal token is revoked on the verdict.
-- No false positives: the manual duplicate INSERT embeds the SAME dispute_round
-- as the RPC wrote, so it genuinely collides on the cycle index.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(15);

-- ── Seeds (as postgres: bypasses RLS) ────────────────────────────────────────
INSERT INTO public.organizations (id, name, cnpj, created_at)
VALUES ('cccccccc-0000-0000-0000-000000000001', 'Org Recycle', '00000000rc0001', NOW())
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.contracts
  (id, organization_id, name, contractor_name, valid_from_utc, valid_until_utc, status)
VALUES
  ('cccccccc-0000-0000-0000-0000000000aa', 'cccccccc-0000-0000-0000-000000000001',
   'Contract Recycle', 'Contractor R', NOW() - INTERVAL '1 year',
   NOW() + INTERVAL '1 year', 'active')
ON CONFLICT (id) DO NOTHING;

-- Active rule version so the OVERTURN arc can seal its inline snapshot (INV-21).
INSERT INTO public.contract_rule_sets (id, organization_id, contract_id)
VALUES ('cccccccc-0000-0000-0000-0000000000c1', 'cccccccc-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-0000000000aa')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.contract_rule_versions
  (id, rule_set_id, rule_type, rule_config, rule_version, evaluation_order,
   active_from_utc, active_to_utc, created_at_utc)
VALUES
  ('cccccccc-0000-0000-0000-0000000000d1', 'cccccccc-0000-0000-0000-0000000000c1',
   'NO_SHOW_PENALTY', '{"penalty_amount_cents": 50000}'::jsonb, 1, 0,
   '2026-01-01T00:00:00Z', NULL, '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING;

-- Two pending queue entries (E1 = accept arc, E2 = overturn arc).
INSERT INTO public.sanction_review_queue
  (id, organization_id, ledger_entry_id, set_id, contract_id, verdict_evidence, status)
VALUES
  ('cccccccc-0000-0000-0000-0000000000e1', 'cccccccc-0000-0000-0000-000000000001',
   'cccccccc-0000-0000-0000-0000000000f1', 'set-accept',
   'cccccccc-0000-0000-0000-0000000000aa', '{}'::jsonb, 'pending'),
  ('cccccccc-0000-0000-0000-0000000000e2', 'cccccccc-0000-0000-0000-000000000001',
   'cccccccc-0000-0000-0000-0000000000f2', 'set-overturn',
   'cccccccc-0000-0000-0000-0000000000aa', '{}'::jsonb, 'pending')
ON CONFLICT (id) DO NOTHING;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"cccccccc-0000-0000-0000-0000000000b9","organization_id":"cccccccc-0000-0000-0000-000000000001","app_metadata":{"org_id":"cccccccc-0000-0000-0000-000000000001","role":"AUDITOR"}}';

-- ════════════════════════════════════════════════════════════════════════════
-- Case 2 (E1): dispute → retract → dispute → DISPUTE_ACCEPTED (Anular)
-- ════════════════════════════════════════════════════════════════════════════

-- 1. Open dispute (round 1).
SELECT lives_ok(
  $$ SELECT public.dispute_sanction(
       'cccccccc-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-0000000000e1',
       'cccccccc-0000-0000-0000-0000000000b9', 'auditor@test.com', '2026-08-23T12:00:00Z') $$,
  'E1 dispute opens (round 1)');

-- 2. Retract (writes DISPUTE_RETRACTED, round 1 → status back to pending).
SELECT lives_ok(
  $$ SELECT public.resolve_dispute(
       'cccccccc-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-0000000000e1',
       'DISPUTE_RETRACTED', 'reopen for evidence', 'cccccccc-0000-0000-0000-0000000000b9',
       'auditor@test.com', '2026-08-23T12:05:00Z',
       'cccccccc-0000-0000-0000-0000000000e1:DISPUTE_RETRACTED:SNAP', NULL) $$,
  'E1 retract succeeds (round 1 RETRACTED)');

-- 3. Re-open dispute (round 2).
SELECT lives_ok(
  $$ SELECT public.dispute_sanction(
       'cccccccc-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-0000000000e1',
       'cccccccc-0000-0000-0000-0000000000b9', 'auditor@test.com', '2026-08-23T12:10:00Z') $$,
  'E1 re-dispute opens (round 2)');

-- Seed an active portal token for E1 (to assert revocation on seal). The token
-- table is deny-all to authenticated, so insert as the superuser session role.
RESET ROLE;
INSERT INTO public.dispute_portal_tokens
  (organization_id, queue_entry_id, created_by_user_id, expires_at_utc, max_access_count)
VALUES
  ('cccccccc-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-0000000000e1',
   'cccccccc-0000-0000-0000-0000000000b9', NOW() + INTERVAL '24 hours', 5);
SET LOCAL ROLE authenticated;

-- 4. ★ REGRESSION: round-2 ACCEPTED would hit 23505 under the old index. Now lives.
SELECT lives_ok(
  $$ SELECT public.resolve_dispute(
       'cccccccc-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-0000000000e1',
       'DISPUTE_ACCEPTED', 'force majeure proven', 'cccccccc-0000-0000-0000-0000000000b9',
       'auditor@test.com', '2026-08-23T12:15:00Z',
       'cccccccc-0000-0000-0000-0000000000e1:DISPUTE_ACCEPTED:SNAP', 'FORCE_MAJEURE') $$,
  'E1 round-2 ACCEPTED no longer collides with round-1 RETRACTED (23505 fixed)');

-- 5. Queue terminal: rejected.
SELECT is(
  (SELECT status FROM public.sanction_review_queue
    WHERE id = 'cccccccc-0000-0000-0000-0000000000e1'),
  'rejected', 'E1 ends rejected after accept arc');

-- 6. dispute_round advanced to 2.
SELECT is(
  (SELECT dispute_round FROM public.sanction_review_queue
    WHERE id = 'cccccccc-0000-0000-0000-0000000000e1'),
  2, 'E1 dispute_round == 2');

-- 7. Exactly one RETRACTED fact in round 1.
SELECT is(
  (SELECT count(*)::int FROM public.sla_audit_ledger_v2
    WHERE payload->>'queue_entry_id' = 'cccccccc-0000-0000-0000-0000000000e1'
      AND type = 'DISPUTE_RETRACTED' AND payload->>'dispute_round' = '1'),
  1, 'E1 round-1 RETRACTED fact present');

-- 8. Exactly one ACCEPTED fact in round 2.
SELECT is(
  (SELECT count(*)::int FROM public.sla_audit_ledger_v2
    WHERE payload->>'queue_entry_id' = 'cccccccc-0000-0000-0000-0000000000e1'
      AND type = 'DISPUTE_ACCEPTED' AND payload->>'dispute_round' = '2'),
  1, 'E1 round-2 ACCEPTED fact present');

-- Token-table reads + the manual ledger INSERT need the superuser session role
-- (token table is deny-all to authenticated; ledger INSERT is RLS/grant-gated).
RESET ROLE;

-- 9. Portal token revoked on the verdict (Revogação de Acesso Externo).
SELECT isnt_empty(
  $$ SELECT id FROM public.dispute_portal_tokens
      WHERE queue_entry_id = 'cccccccc-0000-0000-0000-0000000000e1'
        AND revoked_at_utc IS NOT NULL $$,
  'E1 portal token revoked when sanction judged internally');

-- 10. Revocation reason is VERDICT_SEALED.
SELECT is(
  (SELECT revoked_reason FROM public.dispute_portal_tokens
    WHERE queue_entry_id = 'cccccccc-0000-0000-0000-0000000000e1' LIMIT 1),
  'VERDICT_SEALED', 'E1 token revoked_reason == VERDICT_SEALED');

-- 11. Defense-in-depth: a SAME-cycle (round 2) duplicate ACCEPTED still 23505.
SELECT throws_ok(
  $$ INSERT INTO public.sla_audit_ledger_v2
       (organization_id, type, contract_id, plan_version, occurred_at_utc, payload)
     VALUES
       ('cccccccc-0000-0000-0000-000000000001', 'DISPUTE_ACCEPTED',
        'cccccccc-0000-0000-0000-0000000000aa', 0, '2026-08-23T12:20:00Z',
        '{"queue_entry_id":"cccccccc-0000-0000-0000-0000000000e1","dispute_round":2}'::jsonb) $$,
  '23505', NULL,
  'same-cycle duplicate resolution fact is still blocked (defense-in-depth)');

-- Back to the authenticated auditor for the E2 RPC flow.
SET LOCAL ROLE authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- Case 1 (E2): dispute → retract → dispute → DISPUTE_OVERTURNED (Confirmar)
-- ════════════════════════════════════════════════════════════════════════════

-- 12. Open dispute (round 1).
SELECT lives_ok(
  $$ SELECT public.dispute_sanction(
       'cccccccc-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-0000000000e2',
       'cccccccc-0000-0000-0000-0000000000b9', 'auditor@test.com', '2026-08-23T13:00:00Z') $$,
  'E2 dispute opens (round 1)');

-- 13. Retract.
SELECT lives_ok(
  $$ SELECT public.resolve_dispute(
       'cccccccc-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-0000000000e2',
       'DISPUTE_RETRACTED', 'reopen', 'cccccccc-0000-0000-0000-0000000000b9',
       'auditor@test.com', '2026-08-23T13:05:00Z',
       'cccccccc-0000-0000-0000-0000000000e2:DISPUTE_RETRACTED:SNAP', NULL) $$,
  'E2 retract succeeds');

-- 14. Re-dispute then OVERTURN (seals snapshot) — regression on the overturn arc.
SELECT lives_ok(
  $$ SELECT public.dispute_sanction(
       'cccccccc-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-0000000000e2',
       'cccccccc-0000-0000-0000-0000000000b9', 'auditor@test.com', '2026-08-23T13:10:00Z');
     SELECT public.resolve_dispute(
       'cccccccc-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-0000000000e2',
       'DISPUTE_OVERTURNED', 'evidence reinstated', 'cccccccc-0000-0000-0000-0000000000b9',
       'auditor@test.com', '2026-08-23T13:15:00Z',
       'cccccccc-0000-0000-0000-0000000000e2:DISPUTE_OVERTURNED:SNAP', 'FORCE_MAJEURE') $$,
  'E2 round-2 OVERTURNED seals without 23505');

-- 15. Queue terminal: applied.
SELECT is(
  (SELECT status FROM public.sanction_review_queue
    WHERE id = 'cccccccc-0000-0000-0000-0000000000e2'),
  'applied', 'E2 ends applied after overturn arc');

SELECT * FROM finish();
ROLLBACK;
