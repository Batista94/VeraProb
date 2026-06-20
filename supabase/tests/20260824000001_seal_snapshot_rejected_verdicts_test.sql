BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(6);

-- ── Seeds ────────────────────────────────────────────────────────────────────
-- Org B (own id namespace — no collision with 08* tests).
INSERT INTO public.organizations (
  id, name, legal_name, cnpj, timezone, currency_code,
  plan_type, max_vehicles, max_active_contracts, tool_cost_cents,
  dwell_time_seconds, billing_day, contact_email, external_id,
  organization_type, allowed_domains
) VALUES
  ('00000000-0000-0000-0000-0000000009a1', 'Org B', 'Org B SA', '00000000000901',
   'America/Sao_Paulo', 'BRL', 'enterprise', 1000, 50, 15000, 300, 15,
   'b@test.com', 'EXT_AR_B', 'LOGISTICS', ARRAY['testb.com'])
ON CONFLICT (id) DO NOTHING;

-- Three queue entries covering the three fixed terminal paths.
INSERT INTO public.sanction_review_queue
  (id, organization_id, ledger_entry_id, set_id, contract_id, verdict_evidence, status)
VALUES
  ('00000000-0000-0000-0000-0000000009e1', '00000000-0000-0000-0000-0000000009a1',
   '00000000-0000-0000-0000-0000000009f1', 'set-reject-09',
   '00000000-0000-0000-0000-0000000009aa', '{}'::jsonb, 'pending'),
  ('00000000-0000-0000-0000-0000000009e2', '00000000-0000-0000-0000-0000000009a1',
   '00000000-0000-0000-0000-0000000009f2', 'set-disc-09',
   '00000000-0000-0000-0000-0000000009aa', '{}'::jsonb, 'disputed');

-- pending_peer_review entry: first_reviewer=09b1, proposed REJECT, sub=09b2 will confirm.
INSERT INTO public.sanction_review_queue
  (id, organization_id, ledger_entry_id, set_id, contract_id, verdict_evidence,
   status, first_reviewer_id, peer_review_proposed_action, peer_review_reason_code,
   peer_review_origin_status)
VALUES
  ('00000000-0000-0000-0000-0000000009e3', '00000000-0000-0000-0000-0000000009a1',
   '00000000-0000-0000-0000-0000000009f3', 'set-peer-09',
   '00000000-0000-0000-0000-0000000009aa', '{}'::jsonb,
   'pending_peer_review',
   '00000000-0000-0000-0000-0000000009b1', 'REJECT', 'FORCE_MAJEURE', 'pending');

-- Rule set required by _persist_evidence_snapshot → contract_rule_sets lookup.
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

-- ── AUDITOR JWT (sub = 09b1 — first reviewer) ────────────────────────────────
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-0000000009b1","organization_id":"00000000-0000-0000-0000-0000000009a1","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000009a1","role":"AUDITOR"}}';

-- T1. reject_sanction terminal path now seals forensic snapshot (INV-9, INV-21).
SELECT lives_ok(
  $$ SELECT public.reject_sanction(
       '00000000-0000-0000-0000-0000000009a1',
       '00000000-0000-0000-0000-0000000009e1',
       '00000000-0000-0000-0000-0000000009b1', 'auditor-b@test.com',
       'Evidências GPS inconclusivas para esta rota.', 'FORCE_MAJEURE',
       '2026-08-24T12:00:00Z'
     ) $$,
  'T1: reject_sanction seals forensic snapshot for VERDICT_REFUSED (INV-9, INV-21)'
);

-- T2. Snapshot sealed → verify returns authentic (regression guard: INV-21).
SELECT is(
  (SELECT (public.verify_forensic_evidence_by_queue(
            '00000000-0000-0000-0000-0000000009a1',
            '00000000-0000-0000-0000-0000000009e1'
          ))->>'status'),
  'authentic',
  'T2: rejected entry forensic snapshot is authentic (INV-21)'
);

-- T3. resolve_dispute DISPUTE_ACCEPTED terminal path now seals snapshot (INV-9, INV-21).
SELECT lives_ok(
  $$ SELECT public.resolve_dispute(
       '00000000-0000-0000-0000-0000000009a1',
       '00000000-0000-0000-0000-0000000009e2',
       'DISPUTE_ACCEPTED',
       'Contestação aceita após análise forense.',
       '00000000-0000-0000-0000-0000000009b1', 'auditor-b@test.com',
       '2026-08-24T12:05:00Z',
       'idem-09e2-accept',
       'FORCE_MAJEURE'
     ) $$,
  'T3: resolve_dispute DISPUTE_ACCEPTED seals forensic snapshot (INV-9, INV-21)'
);

-- T4. Snapshot sealed → verify returns authentic.
SELECT is(
  (SELECT (public.verify_forensic_evidence_by_queue(
            '00000000-0000-0000-0000-0000000009a1',
            '00000000-0000-0000-0000-0000000009e2'
          ))->>'status'),
  'authentic',
  'T4: dispute-accepted entry forensic snapshot is authentic (INV-21)'
);

-- ── AUDITOR JWT (sub = 09b2 — second reviewer for dual-control confirm) ──────
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-0000000009b2","organization_id":"00000000-0000-0000-0000-0000000009a1","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000009a1","role":"AUDITOR"}}';

-- T5. confirm_peer_review REJECT path now seals snapshot (INV-9, INV-21).
--     sub=09b2 ≠ first_reviewer=09b1 — passes anti-fraud gate.
SELECT lives_ok(
  $$ SELECT public.confirm_peer_review(
       '00000000-0000-0000-0000-0000000009a1',
       '00000000-0000-0000-0000-0000000009e3',
       '00000000-0000-0000-0000-0000000009b2', 'auditor-b2@test.com',
       '2026-08-24T12:10:00Z',
       'idem-09e3-peer-reject'
     ) $$,
  'T5: confirm_peer_review REJECT seals forensic snapshot for VERDICT_REFUSED (INV-9, INV-21)'
);

-- T6. Snapshot sealed → verify returns authentic.
SELECT is(
  (SELECT (public.verify_forensic_evidence_by_queue(
            '00000000-0000-0000-0000-0000000009a1',
            '00000000-0000-0000-0000-0000000009e3'
          ))->>'status'),
  'authentic',
  'T6: peer-reviewed rejected entry forensic snapshot is authentic (INV-21)'
);

SELECT * FROM finish();
ROLLBACK;
