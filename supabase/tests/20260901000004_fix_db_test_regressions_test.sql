BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(12);

-- ── Seeds ────────────────────────────────────────────────────────────────────
INSERT INTO public.organizations (
  id, name, legal_name, cnpj, timezone, currency_code,
  plan_type, max_vehicles, max_active_contracts, tool_cost_cents,
  dwell_time_seconds, billing_day, contact_email, external_id,
  organization_type, allowed_domains,
  dual_control_threshold_cents
) VALUES
  ('00000000-0000-0000-0000-0000000004a1', 'Org Regress', 'Org Regress SA', '00000000000401',
   'America/Sao_Paulo', 'BRL', 'enterprise', 1000, 50, 15000, 300, 15,
   'regress@test.com', 'EXT_REG_A', 'LOGISTICS', ARRAY['regress.com'],
   99999999) -- Bypass dual-control by setting high threshold!
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.contract_rule_sets (id, organization_id, contract_id)
VALUES ('00000000-0000-0000-0000-0000000004c1',
        '00000000-0000-0000-0000-0000000004a1',
        '00000000-0000-0000-0000-0000000004aa')
ON CONFLICT DO NOTHING;

INSERT INTO public.contract_rule_versions
  (id, rule_set_id, rule_type, rule_config, rule_version, evaluation_order,
   active_from_utc, active_to_utc, created_at_utc)
VALUES
  ('00000000-0000-0000-0000-0000000004d1',
   '00000000-0000-0000-0000-0000000004c1',
   'MAX_TOLERANCE_DELAY', '{"threshold_minutes": 30}'::jsonb, 1, 0,
   '2026-01-01T00:00:00Z', NULL, '2026-01-01T00:00:00Z')
ON CONFLICT DO NOTHING;

INSERT INTO public.sanction_review_queue
  (id, organization_id, ledger_entry_id, set_id, contract_id, verdict_evidence, status, vehicle_plate)
VALUES
  ('00000000-0000-0000-0000-0000000004e1', '00000000-0000-0000-0000-0000000004a1',
   '00000000-0000-0000-0000-0000000004f1', 'set-reg-1',
   '00000000-0000-0000-0000-0000000004aa', '{"fine_cents": 5000, "primary_evidence_timestamp_utc": "2026-06-24T10:00:00Z", "primary_evidence_lat": -23.55, "primary_evidence_lng": -46.63}'::jsonb,
   'disputed', 'ABC-1111'),
  ('00000000-0000-0000-0000-0000000004e2', '00000000-0000-0000-0000-0000000004a1',
   '00000000-0000-0000-0000-0000000004f2', 'set-reg-2',
   '00000000-0000-0000-0000-0000000004aa', '{"fine_cents": 7000, "primary_evidence_timestamp_utc": "2026-06-24T10:00:00Z", "primary_evidence_lat": -23.55, "primary_evidence_lng": -46.63}'::jsonb,
   'pending', 'DEF-2222'),
  ('00000000-0000-0000-0000-0000000004e3', '00000000-0000-0000-0000-0000000004a1',
   '00000000-0000-0000-0000-0000000004f3', 'set-reg-3',
   '00000000-0000-0000-0000-0000000004aa', '{"fine_cents": 9000, "primary_evidence_timestamp_utc": "2026-06-24T10:00:00Z", "primary_evidence_lat": -23.55, "primary_evidence_lng": -46.63}'::jsonb,
   'pending', 'GHI-3333'),
  ('00000000-0000-0000-0000-0000000004e4', '00000000-0000-0000-0000-0000000004a1',
   '00000000-0000-0000-0000-0000000004f4', 'set-reg-4',
   '00000000-0000-0000-0000-0000000004aa', '{"fine_cents": 8000, "primary_evidence_timestamp_utc": "2026-06-24T10:00:00Z", "primary_evidence_lat": -23.55, "primary_evidence_lng": -46.63}'::jsonb,
   'applied', 'JKL-4444');

-- Create tokens for portal access
INSERT INTO public.dispute_portal_tokens
  (token, organization_id, queue_entry_id, expires_at_utc, max_access_count, access_count, created_by_user_id)
VALUES
  ('00000000-0000-0000-0000-0000000004d1', '00000000-0000-0000-0000-0000000004a1',
   '00000000-0000-0000-0000-0000000004e2', '2026-06-25T11:00:00Z', 10, 0, '00000000-0000-0000-0000-0000000004b1'),
  ('00000000-0000-0000-0000-0000000004d2', '00000000-0000-0000-0000-0000000004a1',
   '00000000-0000-0000-0000-0000000004e3', '2026-06-25T11:00:00Z', 10, 0, '00000000-0000-0000-0000-0000000004b1'),
  ('00000000-0000-0000-0000-0000000004d3', '00000000-0000-0000-0000-0000000004a1',
   '00000000-0000-0000-0000-0000000004e4', '2026-06-25T11:00:00Z', 10, 0, '00000000-0000-0000-0000-0000000004b1');

-- ── 1. Test read_infraction_context unmasked pending/applied status (Regressions Fixed) ──
SET LOCAL ROLE anon;

-- pending token: should NOT be masked now (due to fix in 20260901000004)
SELECT is(
  (SELECT (public.read_infraction_context('00000000-0000-0000-0000-0000000004d1') ->> 'asset_identifier')),
  'DEF-2222',
  'T1: pending status token returns UNMASKED asset plate'
);

SELECT is(
  (SELECT (public.read_infraction_context('00000000-0000-0000-0000-0000000004d1') ->> 'penalty_value_cents')::int),
  7000,
  'T2: pending status token returns UNMASKED penalty value'
);

-- ── 2. Test auditing executions with RLS ─────────────────────────────────────
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-0000000004b1","organization_id":"00000000-0000-0000-0000-0000000004a1","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000004a1","role":"AUDITOR"}}';

-- Test resolve_dispute 9-arg signature with DISPUTE_ACCEPTED (restoring snap)
SELECT lives_ok(
  $$ SELECT public.resolve_dispute(
       '00000000-0000-0000-0000-0000000004a1',
       '00000000-0000-0000-0000-0000000004e1',
       'DISPUTE_ACCEPTED',
       'Valid justification provided.',
       '00000000-0000-0000-0000-0000000004b1', 'auditor@test.com',
       '2026-06-24T11:00:00Z', 'idem-reg-dispute', 'FORCE_MAJEURE'
     ) $$,
  'T3: resolve_dispute DISPUTE_ACCEPTED runs successfully with 9-arg signature'
);

-- Verify snapshot was created (inv-21 snapshot seal check for DISPUTE_ACCEPTED)
SELECT is(
  (SELECT count(*)::int FROM public.forensic_evidence_snapshots s
     JOIN public.sla_audit_ledger_v2 l ON l.id = s.ledger_entry_id
    WHERE s.organization_id = '00000000-0000-0000-0000-0000000004a1'
      AND l.payload->>'queue_entry_id' = '00000000-0000-0000-0000-0000000004e1'),
  1,
  'T4: DISPUTE_ACCEPTED seals exactly one forensic snapshot'
);

-- Test approve_sanction 7-arg signature (restoring snap)
SELECT lives_ok(
  $$ SELECT public.approve_sanction(
       '00000000-0000-0000-0000-0000000004a1',
       '00000000-0000-0000-0000-0000000004e2',
       '00000000-0000-0000-0000-0000000004b1', 'auditor@test.com',
       '2026-06-24T11:00:00Z', 'FORCE_MAJEURE', 'Confirm fine is correct.'
     ) $$,
  'T5: approve_sanction runs successfully with 7-arg signature'
);

-- Verify status changed to applied
SELECT is(
  (SELECT status FROM public.sanction_review_queue WHERE id = '00000000-0000-0000-0000-0000000004e2'),
  'applied',
  'T6: approve_sanction transitions status to applied'
);

-- Verify snapshot created (VERDICT_SEALED)
SELECT is(
  (SELECT count(*)::int FROM public.forensic_evidence_snapshots s
     JOIN public.sla_audit_ledger_v2 l ON l.id = s.ledger_entry_id
    WHERE s.organization_id = '00000000-0000-0000-0000-0000000004a1'
      AND l.payload->>'queue_entry_id' = '00000000-0000-0000-0000-0000000004e2'),
  1,
  'T7: approve_sanction seals exactly one forensic snapshot'
);

-- Test reject_sanction 7-arg signature (restoring snap)
SELECT lives_ok(
  $$ SELECT public.reject_sanction(
       '00000000-0000-0000-0000-0000000004a1',
       '00000000-0000-0000-0000-0000000004e3',
       '00000000-0000-0000-0000-0000000004b1', 'auditor@test.com',
       'Rejecting this fine completely.', 'FORCE_MAJEURE',
       '2026-06-24T11:00:00Z'
     ) $$,
  'T8: reject_sanction runs successfully with 7-arg signature'
);

-- Verify status changed to rejected
SELECT is(
  (SELECT status FROM public.sanction_review_queue WHERE id = '00000000-0000-0000-0000-0000000004e3'),
  'rejected',
  'T9: reject_sanction transitions status to rejected'
);

-- Verify snapshot created (VERDICT_REFUSED)
SELECT is(
  (SELECT count(*)::int FROM public.forensic_evidence_snapshots s
     JOIN public.sla_audit_ledger_v2 l ON l.id = s.ledger_entry_id
    WHERE s.organization_id = '00000000-0000-0000-0000-0000000004a1'
      AND l.payload->>'queue_entry_id' = '00000000-0000-0000-0000-0000000004e3'),
  1,
  'T10: reject_sanction seals exactly one forensic snapshot'
);

-- ── 3. Test read_infraction_context unmasked applied status (Regression Fixed) ──
SET LOCAL ROLE anon;

-- applied token (from e4): should NOT be masked now
SELECT is(
  (SELECT (public.read_infraction_context('00000000-0000-0000-0000-0000000004d3') ->> 'asset_identifier')),
  'JKL-4444',
  'T11: applied status token returns UNMASKED asset plate'
);

SELECT is(
  (SELECT (public.read_infraction_context('00000000-0000-0000-0000-0000000004d3') ->> 'penalty_value_cents')::int),
  8000,
  'T12: applied status token returns UNMASKED penalty value'
);

SELECT * FROM finish();
ROLLBACK;
