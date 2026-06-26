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
  ('00000000-0000-0000-0000-0000000006a1', 'Org Claims', 'Org Claims SA', '00000000000601',
   'America/Sao_Paulo', 'BRL', 'enterprise', 1000, 50, 15000, 300, 15,
   'claims@test.com', 'EXT_CLA_A', 'LOGISTICS', ARRAY['claims.com'],
   99999999) -- Bypass dual-control by setting high threshold
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.contract_rule_sets (id, organization_id, contract_id)
VALUES ('00000000-0000-0000-0000-0000000006c1',
        '00000000-0000-0000-0000-0000000006a1',
        '00000000-0000-0000-0000-0000000006aa')
ON CONFLICT DO NOTHING;

INSERT INTO public.contract_rule_versions
  (id, rule_set_id, rule_type, rule_config, rule_version, evaluation_order,
   active_from_utc, active_to_utc, created_at_utc)
VALUES
  ('00000000-0000-0000-0000-0000000006d1',
   '00000000-0000-0000-0000-0000000006c1',
   'MAX_TOLERANCE_DELAY', '{"threshold_minutes": 30}'::jsonb, 1, 0,
   '2026-01-01T00:00:00Z', NULL, '2026-01-01T00:00:00Z')
ON CONFLICT DO NOTHING;

INSERT INTO public.sanction_review_queue
  (id, organization_id, ledger_entry_id, set_id, contract_id, verdict_evidence, status, vehicle_plate)
VALUES
  ('00000000-0000-0000-0000-0000000006e1', '00000000-0000-0000-0000-0000000006a1',
   '00000000-0000-0000-0000-0000000006f1', 'set-cla-1',
   '00000000-0000-0000-0000-0000000006aa', '{"fine_cents": 5000, "primary_evidence_timestamp_utc": "2026-06-24T10:00:00Z", "primary_evidence_lat": -23.55, "primary_evidence_lng": -46.63}'::jsonb,
   'disputed', 'ABC-1111'),
  ('00000000-0000-0000-0000-0000000006e2', '00000000-0000-0000-0000-0000000006a1',
   '00000000-0000-0000-0000-0000000006f2', 'set-cla-2',
   '00000000-0000-0000-0000-0000000006aa', '{"fine_cents": 7000, "primary_evidence_timestamp_utc": "2026-06-24T10:00:00Z", "primary_evidence_lat": -23.55, "primary_evidence_lng": -46.63}'::jsonb,
   'pending', 'DEF-2222'),
  ('00000000-0000-0000-0000-0000000006e3', '00000000-0000-0000-0000-0000000006a1',
   '00000000-0000-0000-0000-0000000006f3', 'set-cla-3',
   '00000000-0000-0000-0000-0000000006aa', '{"fine_cents": 9000, "primary_evidence_timestamp_utc": "2026-06-24T10:00:00Z", "primary_evidence_lat": -23.55, "primary_evidence_lng": -46.63}'::jsonb,
   'pending', 'GHI-3333');

-- Ensure dispute reason code exists
INSERT INTO public.dispute_reason_codes (code, category, label_pt, label_en, description, is_active, organization_id)
VALUES ('FORCE_MAJEURE', 'ENVIRONMENTAL', 'Força Maior', 'Force Majeure', 'Force Majeure Event', TRUE, NULL)
ON CONFLICT (code) DO NOTHING;

-- ── 1. Verify that top-level JWT organization_id claim allows access ──
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-0000000006b1","organization_id":"00000000-0000-0000-0000-0000000006a1","app_metadata":{"role":"AUDITOR"}}';

-- resolve_dispute should succeed
SELECT lives_ok(
  $$ SELECT public.resolve_dispute(
       '00000000-0000-0000-0000-0000000006a1',
       '00000000-0000-0000-0000-0000000006e1',
       'DISPUTE_ACCEPTED',
       'Valid justification provided.',
       '00000000-0000-0000-0000-0000000006b1', 'auditor@test.com',
       '2026-06-24T11:00:00Z', 'idem-claims-dispute', 'FORCE_MAJEURE'
     ) $$,
  'T1: resolve_dispute succeeds when JWT organization_id matches parameter'
);

-- approve_sanction should succeed
SELECT lives_ok(
  $$ SELECT public.approve_sanction(
       '00000000-0000-0000-0000-0000000006a1',
       '00000000-0000-0000-0000-0000000006e2',
       '00000000-0000-0000-0000-0000000006b1', 'auditor@test.com',
       '2026-06-24T11:00:00Z', 'FORCE_MAJEURE', 'Confirm fine is correct.'
     ) $$,
  'T2: approve_sanction succeeds when JWT organization_id matches parameter'
);

-- reject_sanction should succeed
SELECT lives_ok(
  $$ SELECT public.reject_sanction(
       '00000000-0000-0000-0000-0000000006a1',
       '00000000-0000-0000-0000-0000000006e3',
       '00000000-0000-0000-0000-0000000006b1', 'auditor@test.com',
       'Rejecting this fine completely.', 'FORCE_MAJEURE',
       '2026-06-24T11:00:00Z'
     ) $$,
  'T3: reject_sanction succeeds when JWT organization_id matches parameter'
);

-- ── 2. Verify that mismatched JWT organization_id claim blocks access ──
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-0000000006b1","organization_id":"00000000-0000-0000-0000-0000000006a2","app_metadata":{"role":"AUDITOR"}}';

SELECT throws_ok(
  $$ SELECT public.resolve_dispute(
       '00000000-0000-0000-0000-0000000006a1',
       '00000000-0000-0000-0000-0000000006e1',
       'DISPUTE_ACCEPTED',
       'Valid justification provided.',
       '00000000-0000-0000-0000-0000000006b1', 'auditor@test.com',
       '2026-06-24T11:00:00Z', 'idem-claims-dispute-fail', 'FORCE_MAJEURE'
     ) $$,
  '42501',
  NULL,
  'T4: resolve_dispute blocks access when JWT organization_id does not match parameter'
);

SELECT throws_ok(
  $$ SELECT public.approve_sanction(
       '00000000-0000-0000-0000-0000000006a1',
       '00000000-0000-0000-0000-0000000006e2',
       '00000000-0000-0000-0000-0000000006b1', 'auditor@test.com',
       '2026-06-24T11:00:00Z', 'FORCE_MAJEURE', 'Confirm fine is correct.'
     ) $$,
  '42501',
  NULL,
  'T5: approve_sanction blocks access when JWT organization_id does not match parameter'
);

SELECT throws_ok(
  $$ SELECT public.reject_sanction(
       '00000000-0000-0000-0000-0000000006a1',
       '00000000-0000-0000-0000-0000000006e3',
       '00000000-0000-0000-0000-0000000006b1', 'auditor@test.com',
       'Rejecting this fine completely.', 'FORCE_MAJEURE',
       '2026-06-24T11:00:00Z'
     ) $$,
  '42501',
  NULL,
  'T6: reject_sanction blocks access when JWT organization_id does not match parameter'
);

-- ── 3. Verify that null JWT organization_id claim blocks access ──
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-0000000006b1","app_metadata":{"role":"AUDITOR"}}';

SELECT throws_ok(
  $$ SELECT public.approve_sanction(
       '00000000-0000-0000-0000-0000000006a1',
       '00000000-0000-0000-0000-0000000006e2',
       '00000000-0000-0000-0000-0000000006b1', 'auditor@test.com',
       '2026-06-24T11:00:00Z', 'FORCE_MAJEURE', 'Confirm fine is correct.'
     ) $$,
  '42501',
  NULL,
  'T7: approve_sanction blocks access when JWT organization_id is null'
);

-- ── 4. Verify that non-auditor role blocks access ──
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-0000000006b1","organization_id":"00000000-0000-0000-0000-0000000006a1","app_metadata":{"role":"USER"}}';

SELECT throws_ok(
  $$ SELECT public.approve_sanction(
       '00000000-0000-0000-0000-0000000006a1',
       '00000000-0000-0000-0000-0000000006e2',
       '00000000-0000-0000-0000-0000000006b1', 'auditor@test.com',
       '2026-06-24T11:00:00Z', 'FORCE_MAJEURE', 'Confirm fine is correct.'
     ) $$,
  '42501',
  NULL,
  'T8: approve_sanction blocks access when JWT user role is not AUDITOR or TENANT_ADMIN'
);

SELECT * FROM finish();
ROLLBACK;
