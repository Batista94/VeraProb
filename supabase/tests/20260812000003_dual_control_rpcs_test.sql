BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(34);

-- ── Seeds ────────────────────────────────────────────────────────────────────
-- Org A: dual-control ON at 100000 cents (R$ 1.000,00), TTL 48h.
INSERT INTO public.organizations (
  id, name, legal_name, cnpj, timezone, currency_code,
  plan_type, max_vehicles, max_active_contracts, tool_cost_cents,
  dwell_time_seconds, billing_day, contact_email, external_id,
  organization_type, allowed_domains, dual_control_threshold_cents,
  dual_control_ttl_hours
) VALUES
  ('00000000-0000-0000-0000-0000000009a1', 'Org DC', 'Org DC SA', '00000000000901',
   'America/Sao_Paulo', 'BRL', 'enterprise', 1000, 50, 15000, 300, 15,
   'dc@test.com', 'EXT_DC_A', 'LOGISTICS', ARRAY['test.com'], 100000, 48)
ON CONFLICT (id) DO NOTHING;

-- Contract aa: no override (inherits org). Contract ab: override at 10000 cents.
INSERT INTO public.contracts
  (id, organization_id, name, contractor_name, valid_from_utc, valid_until_utc,
   status, dual_control_threshold_cents)
VALUES
  ('00000000-0000-0000-0000-0000000009aa', '00000000-0000-0000-0000-0000000009a1',
   'Contract AA', 'Carrier AA', '2026-01-01T00:00:00Z', '2027-01-01T00:00:00Z',
   'active', NULL),
  ('00000000-0000-0000-0000-0000000009ab', '00000000-0000-0000-0000-0000000009a1',
   'Contract AB', 'Carrier AB', '2026-01-01T00:00:00Z', '2027-01-01T00:00:00Z',
   'active', 10000)
ON CONFLICT (id) DO NOTHING;

-- Queue entries. fine_cents lives in the sealed verdict_evidence (INV-15).
INSERT INTO public.sanction_review_queue
  (id, organization_id, ledger_entry_id, set_id, contract_id, verdict_evidence, status)
VALUES
  ('00000000-0000-0000-0000-0000000009e1', '00000000-0000-0000-0000-0000000009a1',
   '00000000-0000-0000-0000-0000000009f1', 'set-fork', '00000000-0000-0000-0000-0000000009aa',
   '{"fine_cents": 200000}'::jsonb, 'pending'),
  ('00000000-0000-0000-0000-0000000009e2', '00000000-0000-0000-0000-0000000009a1',
   '00000000-0000-0000-0000-0000000009f2', 'set-low', '00000000-0000-0000-0000-0000000009aa',
   '{"fine_cents": 50000}'::jsonb, 'pending'),
  ('00000000-0000-0000-0000-0000000009e3', '00000000-0000-0000-0000-0000000009a1',
   '00000000-0000-0000-0000-0000000009f3', 'set-decline', '00000000-0000-0000-0000-0000000009aa',
   '{"fine_cents": 200000}'::jsonb, 'pending'),
  ('00000000-0000-0000-0000-0000000009e4', '00000000-0000-0000-0000-0000000009a1',
   '00000000-0000-0000-0000-0000000009f4', 'set-expire', '00000000-0000-0000-0000-0000000009aa',
   '{"fine_cents": 200000}'::jsonb, 'pending'),
  ('00000000-0000-0000-0000-0000000009e9', '00000000-0000-0000-0000-0000000009a1',
   '00000000-0000-0000-0000-0000000009f9', 'set-override', '00000000-0000-0000-0000-0000000009ab',
   '{"fine_cents": 50000}'::jsonb, 'pending'),
  -- e5: high-value entry used to exercise the reject_sanction fork + REJECT confirm.
  ('00000000-0000-0000-0000-0000000009e5', '00000000-0000-0000-0000-0000000009a1',
   '00000000-0000-0000-0000-0000000009f5', 'set-reject', '00000000-0000-0000-0000-0000000009aa',
   '{"fine_cents": 200000}'::jsonb, 'pending');

-- Rule set required by approve_sanction terminal path for below-threshold entries.
INSERT INTO public.contract_rule_sets (id, organization_id, contract_id)
VALUES ('00000000-0000-0000-0000-0000000009bb',
        '00000000-0000-0000-0000-0000000009a1',
        '00000000-0000-0000-0000-0000000009aa')
ON CONFLICT DO NOTHING;

INSERT INTO public.contract_rule_versions
  (id, rule_set_id, rule_type, rule_config, rule_version, evaluation_order,
   active_from_utc, active_to_utc, created_at_utc)
VALUES ('00000000-0000-0000-0000-0000000009cc',
        '00000000-0000-0000-0000-0000000009bb',
        'MAX_TOLERANCE_DELAY', '{"threshold_minutes": 30}'::jsonb, 1, 0,
        '2026-01-01T00:00:00Z', NULL, '2026-01-01T00:00:00Z')
ON CONFLICT DO NOTHING;

-- ── Existence + grants ────────────────────────────────────────────────────────
SELECT has_function(
  'public', 'confirm_peer_review',
  ARRAY['uuid', 'uuid', 'uuid', 'text', 'timestamp with time zone', 'text'],
  'confirm_peer_review exists with the expected signature'
);
SELECT is(
  (SELECT prosecdef FROM pg_proc WHERE proname = 'confirm_peer_review'),
  true, 'confirm_peer_review is SECURITY DEFINER'
);
SELECT has_function(
  'public', 'decline_peer_review',
  ARRAY['uuid', 'uuid', 'uuid', 'text', 'text', 'timestamp with time zone'],
  'decline_peer_review exists with the expected signature'
);
SELECT has_function(
  'public', 'expire_stale_peer_reviews', ARRAY[]::text[],
  'expire_stale_peer_reviews exists'
);
SELECT ok(
  has_function_privilege('authenticated',
    'public.confirm_peer_review(uuid, uuid, uuid, text, timestamp with time zone, text)',
    'EXECUTE'),
  'authenticated may execute confirm_peer_review'
);
SELECT ok(
  NOT has_function_privilege('anon',
    'public.confirm_peer_review(uuid, uuid, uuid, text, timestamp with time zone, text)',
    'EXECUTE'),
  'anon may NOT execute confirm_peer_review'
);
SELECT ok(
  has_function_privilege('service_role',
    'public.expire_stale_peer_reviews()', 'EXECUTE'),
  'service_role may execute expire_stale_peer_reviews (scheduled job)'
);
SELECT ok(
  NOT has_function_privilege('authenticated',
    'public.expire_stale_peer_reviews()', 'EXECUTE'),
  'authenticated may NOT execute expire_stale_peer_reviews'
);

-- ── First reviewer (AUDITOR Org A, sub ...09b9) ───────────────────────────────
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-0000000009b9","organization_id":"00000000-0000-0000-0000-0000000009a1","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000009a1","role":"AUDITOR"}}';

-- 9. High-value approve forks into pending_peer_review (does NOT seal).
SELECT lives_ok(
  $$ SELECT public.approve_sanction(
       '00000000-0000-0000-0000-0000000009a1',
       '00000000-0000-0000-0000-0000000009e1',
       '00000000-0000-0000-0000-0000000009b9', 'auditor1@test.com',
       '2026-08-12T12:00:00Z'
     ) $$,
  'high-value approve forks into peer review'
);
-- 10. Status is pending_peer_review.
SELECT is(
  (SELECT status FROM public.sanction_review_queue
    WHERE id = '00000000-0000-0000-0000-0000000009e1'),
  'pending_peer_review', 'forked verdict holds in pending_peer_review'
);
-- 11. first_reviewer_id captured from the requester.
SELECT is(
  (SELECT first_reviewer_id FROM public.sanction_review_queue
    WHERE id = '00000000-0000-0000-0000-0000000009e1'),
  '00000000-0000-0000-0000-0000000009b9'::uuid,
  'first_reviewer_id is the requesting auditor'
);
-- 12. Exactly one PEER_REVIEW_REQUESTED fact (no terminal verdict yet).
SELECT is(
  (SELECT count(*)::int FROM public.sla_audit_ledger_v2
    WHERE type = 'PEER_REVIEW_REQUESTED'
      AND payload->>'queue_entry_id' = '00000000-0000-0000-0000-0000000009e1'),
  1, 'one PEER_REVIEW_REQUESTED fact appended, no VERDICT_SEALED'
);

-- 13. Below-threshold approve goes terminal (no fork).
SELECT lives_ok(
  $$ SELECT public.approve_sanction(
       '00000000-0000-0000-0000-0000000009a1',
       '00000000-0000-0000-0000-0000000009e2',
       '00000000-0000-0000-0000-0000000009b9', 'auditor1@test.com',
       '2026-08-12T12:01:00Z'
     ) $$,
  'below-threshold approve executes'
);
SELECT is(
  (SELECT status FROM public.sanction_review_queue
    WHERE id = '00000000-0000-0000-0000-0000000009e2'),
  'applied', 'below-threshold approve goes terminal (no peer review)'
);

-- 14. Contract override (10000 < 50000) forks even though org baseline (100000)
--     would not — COALESCE(contract, org).
SELECT lives_ok(
  $$ SELECT public.approve_sanction(
       '00000000-0000-0000-0000-0000000009a1',
       '00000000-0000-0000-0000-0000000009e9',
       '00000000-0000-0000-0000-0000000009b9', 'auditor1@test.com',
       '2026-08-12T12:02:00Z'
     ) $$,
  'contract-override approve executes'
);
SELECT is(
  (SELECT status FROM public.sanction_review_queue
    WHERE id = '00000000-0000-0000-0000-0000000009e9'),
  'pending_peer_review',
  'contract threshold override forks below the org baseline'
);

-- reject_sanction (WAIVE direction) ALSO forks high-value verdicts — the collusion
-- vector of Item 2 is unjust *waiving*, so the fork must cover reject, not just approve.
SELECT lives_ok(
  $$ SELECT public.reject_sanction(
       '00000000-0000-0000-0000-0000000009a1',
       '00000000-0000-0000-0000-0000000009e5',
       '00000000-0000-0000-0000-0000000009b9', 'auditor1@test.com',
       'Carrier disputes the GPS trace.', 'FORCE_MAJEURE', '2026-08-12T12:02:30Z'
     ) $$,
  'high-value reject forks into peer review'
);
SELECT is(
  (SELECT status || ':' || peer_review_proposed_action
     FROM public.sanction_review_queue
    WHERE id = '00000000-0000-0000-0000-0000000009e5'),
  'pending_peer_review:REJECT',
  'reject fork records REJECT as the proposed terminal action'
);

-- Prepare e3 (decline) + e4 (expire) in pending_peer_review.
-- PERFORM so these setup calls do not emit TAP rows (keeps the plan exact).
DO $$
BEGIN
  PERFORM public.approve_sanction(
    '00000000-0000-0000-0000-0000000009a1',
    '00000000-0000-0000-0000-0000000009e3',
    '00000000-0000-0000-0000-0000000009b9', 'auditor1@test.com',
    '2026-08-12T12:03:00Z');
  PERFORM public.approve_sanction(
    '00000000-0000-0000-0000-0000000009a1',
    '00000000-0000-0000-0000-0000000009e4',
    '00000000-0000-0000-0000-0000000009b9', 'auditor1@test.com',
    '2026-08-12T12:04:00Z');
END $$;

-- ★ 15. SELF-APPROVAL BLOCKED: the requester cannot confirm their own verdict.
SELECT throws_ok(
  $$ SELECT public.confirm_peer_review(
       '00000000-0000-0000-0000-0000000009a1',
       '00000000-0000-0000-0000-0000000009e1',
       '00000000-0000-0000-0000-0000000009b9', 'auditor1@test.com',
       '2026-08-12T12:05:00Z', 'idem-e1'
     ) $$,
  'P0001', NULL,
  'requester cannot self-confirm (DualControlSelfApprovalException)'
);

-- ── Adverse / security parity (anti-oracle, RBAC, tenant isolation) ───────────
-- Each call targets e4 (held in pending_peer_review) or a non-existent id and MUST
-- throw WITHOUT mutating state, so e4 survives for the expiry sweep below. A direct
-- RPC hit bypasses the Dart handler guards — this is where INV-22/INV-26 must hold.

-- Cross-tenant: an auditor of ANOTHER org confirming an Org-A item → 42501.
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-0000000009d9","organization_id":"00000000-0000-0000-0000-00000000aaaa","app_metadata":{"org_id":"00000000-0000-0000-0000-00000000aaaa","role":"AUDITOR"}}';
SELECT throws_ok(
  $$ SELECT public.confirm_peer_review(
       '00000000-0000-0000-0000-0000000009a1',
       '00000000-0000-0000-0000-0000000009e4',
       '00000000-0000-0000-0000-0000000009d9', 'attacker@evil.com',
       '2026-08-12T12:05:10Z', 'idem-x1'
     ) $$,
  '42501', NULL,
  'cross-tenant confirm raises the anti-oracle 42501 (INV-22)'
);

-- Cross-tenant decline parity → 42501.
SELECT throws_ok(
  $$ SELECT public.decline_peer_review(
       '00000000-0000-0000-0000-0000000009a1',
       '00000000-0000-0000-0000-0000000009e4',
       '00000000-0000-0000-0000-0000000009d9', 'attacker@evil.com',
       'malicious', '2026-08-12T12:05:11Z'
     ) $$,
  '42501', NULL,
  'cross-tenant decline raises 42501'
);

-- NULL JWT (no app_metadata.org_id) → 42501 (fail-closed, INV-1).
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-0000000009c9"}';
SELECT throws_ok(
  $$ SELECT public.confirm_peer_review(
       '00000000-0000-0000-0000-0000000009a1',
       '00000000-0000-0000-0000-0000000009e4',
       '00000000-0000-0000-0000-0000000009c9', 'auditor2@test.com',
       '2026-08-12T12:05:12Z', 'idem-x2'
     ) $$,
  '42501', NULL,
  'confirm with a JWT lacking org_id is rejected (fail-closed)'
);

-- Wrong role (OPERATOR) confirming → 42501. RBAC enforced at the RPC, not only UI.
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-0000000009c9","organization_id":"00000000-0000-0000-0000-0000000009a1","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000009a1","role":"OPERATOR"}}';
SELECT throws_ok(
  $$ SELECT public.confirm_peer_review(
       '00000000-0000-0000-0000-0000000009a1',
       '00000000-0000-0000-0000-0000000009e4',
       '00000000-0000-0000-0000-0000000009c9', 'auditor2@test.com',
       '2026-08-12T12:05:13Z', 'idem-x3'
     ) $$,
  '42501', NULL,
  'an OPERATOR cannot confirm a peer review (RBAC at the RPC)'
);

-- Not-found (valid Org-A auditor, non-existent item) → SAME 42501 as wrong-org.
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-0000000009c9","organization_id":"00000000-0000-0000-0000-0000000009a1","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000009a1","role":"AUDITOR"}}';
SELECT throws_ok(
  $$ SELECT public.confirm_peer_review(
       '00000000-0000-0000-0000-0000000009a1',
       '00000000-0000-0000-0000-00000000dead',
       '00000000-0000-0000-0000-0000000009c9', 'auditor2@test.com',
       '2026-08-12T12:05:14Z', 'idem-x4'
     ) $$,
  '42501', NULL,
  'not-found confirm raises the SAME 42501 as wrong-org (anti-oracle, INV-26)'
);

-- ── Second, DISTINCT reviewer (AUDITOR Org A, sub ...09c9) ────────────────────
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-0000000009c9","organization_id":"00000000-0000-0000-0000-0000000009a1","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000009a1","role":"AUDITOR"}}';

-- 16. Distinct second auditor confirms → terminal.
SELECT lives_ok(
  $$ SELECT public.confirm_peer_review(
       '00000000-0000-0000-0000-0000000009a1',
       '00000000-0000-0000-0000-0000000009e1',
       '00000000-0000-0000-0000-0000000009c9', 'auditor2@test.com',
       '2026-08-12T12:06:00Z', 'idem-e1'
     ) $$,
  'distinct second auditor confirms the verdict'
);
-- 17. Status now applied (proposed action was APPROVE).
SELECT is(
  (SELECT status FROM public.sanction_review_queue
    WHERE id = '00000000-0000-0000-0000-0000000009e1'),
  'applied', 'confirm applies the proposed terminal action'
);
-- 18. Terminal fact carries BOTH signatures (dual-signature SOC2 trail).
SELECT is(
  (SELECT count(*)::int FROM public.sla_audit_ledger_v2
    WHERE type = 'VERDICT_SEALED'
      AND payload->>'queue_entry_id' = '00000000-0000-0000-0000-0000000009e1'
      AND payload->>'first_reviewer_id' = '00000000-0000-0000-0000-0000000009b9'
      AND payload->>'second_reviewer_id' = '00000000-0000-0000-0000-0000000009c9'),
  1, 'terminal fact records first_reviewer_id and second_reviewer_id'
);

-- Idempotency: a second confirm on an already-terminal item loses (P0001).
SELECT throws_ok(
  $$ SELECT public.confirm_peer_review(
       '00000000-0000-0000-0000-0000000009a1',
       '00000000-0000-0000-0000-0000000009e1',
       '00000000-0000-0000-0000-0000000009c9', 'auditor2@test.com',
       '2026-08-12T12:06:30Z', 'idem-e1'
     ) $$,
  'P0001', NULL,
  'second confirm on a sealed item is rejected (IdempotencyProcessingException)'
);

-- Non-APPROVE proposed action: confirming the REJECT fork (e5) waives terminally.
SELECT lives_ok(
  $$ SELECT public.confirm_peer_review(
       '00000000-0000-0000-0000-0000000009a1',
       '00000000-0000-0000-0000-0000000009e5',
       '00000000-0000-0000-0000-0000000009c9', 'auditor2@test.com',
       '2026-08-12T12:06:45Z', 'idem-e5'
     ) $$,
  'distinct second auditor confirms a REJECT fork'
);
SELECT is(
  (SELECT status FROM public.sanction_review_queue
    WHERE id = '00000000-0000-0000-0000-0000000009e5'),
  'rejected', 'confirming a REJECT fork waives the sanction terminally'
);
SELECT is(
  (SELECT count(*)::int FROM public.sla_audit_ledger_v2
    WHERE type = 'VERDICT_REFUSED'
      AND payload->>'queue_entry_id' = '00000000-0000-0000-0000-0000000009e5'
      AND payload->>'first_reviewer_id' = '00000000-0000-0000-0000-0000000009b9'
      AND payload->>'second_reviewer_id' = '00000000-0000-0000-0000-0000000009c9'),
  1, 'REJECT confirm seals VERDICT_REFUSED with both signatures'
);

-- 19. Decline reverts to the origin status (pending).
SELECT lives_ok(
  $$ SELECT public.decline_peer_review(
       '00000000-0000-0000-0000-0000000009a1',
       '00000000-0000-0000-0000-0000000009e3',
       '00000000-0000-0000-0000-0000000009c9', 'auditor2@test.com',
       'Insufficient context to co-sign.', '2026-08-12T12:07:00Z'
     ) $$,
  'decline executes'
);
SELECT is(
  (SELECT status FROM public.sanction_review_queue
    WHERE id = '00000000-0000-0000-0000-0000000009e3'),
  'pending', 'decline reverts the item to its origin (pending)'
);

-- ── Expiry sweep (SYSTEM actor, no JWT) ───────────────────────────────────────
RESET ROLE;
UPDATE public.sanction_review_queue
   SET peer_review_expires_at = '2020-01-01T00:00:00Z'
 WHERE id = '00000000-0000-0000-0000-0000000009e4';
DO $$ BEGIN PERFORM public.expire_stale_peer_reviews(); END $$;

-- 20. Expired item reverted to origin + PEER_REVIEW_EXPIRED appended.
SELECT is(
  (SELECT status FROM public.sanction_review_queue
    WHERE id = '00000000-0000-0000-0000-0000000009e4')
    || ':' ||
  (SELECT count(*)::text FROM public.sla_audit_ledger_v2
    WHERE type = 'PEER_REVIEW_EXPIRED'
      AND payload->>'queue_entry_id' = '00000000-0000-0000-0000-0000000009e4'),
  'pending:1',
  'stale peer review expires back to origin with a PEER_REVIEW_EXPIRED fact'
);

SELECT * FROM finish();
ROLLBACK;
