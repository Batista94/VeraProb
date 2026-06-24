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
  ('00000000-0000-0000-0000-0000000003a1', 'Org Masking', 'Org Masking SA', '00000000000301',
   'America/Sao_Paulo', 'BRL', 'enterprise', 1000, 50, 15000, 300, 15,
   'masking@test.com', 'EXT_MSK_A', 'LOGISTICS', ARRAY['masking.com'],
   99999999)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.sanction_review_queue
  (id, organization_id, ledger_entry_id, set_id, contract_id, verdict_evidence, status, vehicle_plate)
VALUES
  ('00000000-0000-0000-0000-0000000003e1', '00000000-0000-0000-0000-0000000003a1',
   '00000000-0000-0000-0000-0000000003f1', 'set-mask-1',
   '00000000-0000-0000-0000-0000000003aa', '{"fine_cents": 5000, "primary_evidence_timestamp_utc": "2026-06-24T10:00:00Z", "primary_evidence_lat": -23.55, "primary_evidence_lng": -46.63}'::jsonb,
   'disputed', 'ABC-1234'),
  ('00000000-0000-0000-0000-0000000003e2', '00000000-0000-0000-0000-0000000003a1',
   '00000000-0000-0000-0000-0000000003f2', 'set-mask-2',
   '00000000-0000-0000-0000-0000000003aa', '{"fine_cents": 7000, "primary_evidence_timestamp_utc": "2026-06-24T10:00:00Z", "primary_evidence_lat": -23.55, "primary_evidence_lng": -46.63}'::jsonb,
   'rejected', 'DEF-5678');

-- Create tokens for portal access
INSERT INTO public.dispute_portal_tokens
  (token, organization_id, queue_entry_id, expires_at_utc, max_access_count, access_count, created_by_user_id)
VALUES
  ('00000000-0000-0000-0000-0000000003d1', '00000000-0000-0000-0000-0000000003a1',
   '00000000-0000-0000-0000-0000000003e1', '2026-06-25T11:00:00Z', 10, 0, '00000000-0000-0000-0000-0000000003b1'),
  ('00000000-0000-0000-0000-0000000003d2', '00000000-0000-0000-0000-0000000003a1',
   '00000000-0000-0000-0000-0000000003e2', '2026-06-25T11:00:00Z', 10, 0, '00000000-0000-0000-0000-0000000003b1');

-- Run tests as anonymous (representing the portal carrier access)
SET LOCAL ROLE anon;

-- ── 1. Test unmasked read for 'disputed' state ───────────────────────────────
SELECT lives_ok(
  $$ SELECT public.read_infraction_context('00000000-0000-0000-0000-0000000003d1') $$,
  'T1: read_infraction_context runs on disputed token'
);

SELECT is(
  (SELECT (public.read_infraction_context('00000000-0000-0000-0000-0000000003d1') ->> 'asset_identifier')),
  'ABC-1234',
  'T2: disputed status returns unmasked plate'
);

SELECT is(
  (SELECT (public.read_infraction_context('00000000-0000-0000-0000-0000000003d1') ->> 'penalty_value_cents')::int),
  5000,
  'T3: disputed status returns unmasked penalty value'
);

SELECT is(
  (SELECT (public.read_infraction_context('00000000-0000-0000-0000-0000000003d1') ->> 'primary_evidence_lat')::numeric),
  -23.55,
  'T4: disputed status returns unmasked latitude'
);

-- ── 2. Test masked read for 'rejected' state ─────────────────────────────────
SELECT lives_ok(
  $$ SELECT public.read_infraction_context('00000000-0000-0000-0000-0000000003d2') $$,
  'T5: read_infraction_context runs on rejected token'
);

SELECT is(
  (SELECT (public.read_infraction_context('00000000-0000-0000-0000-0000000003d2') ->> 'asset_identifier')),
  NULL,
  'T6: rejected status returns MASKED (NULL) plate'
);

SELECT is(
  (SELECT (public.read_infraction_context('00000000-0000-0000-0000-0000000003d2') ->> 'penalty_value_cents')),
  NULL,
  'T7: rejected status returns MASKED (NULL) penalty'
);

SELECT is(
  (SELECT (public.read_infraction_context('00000000-0000-0000-0000-0000000003d2') ->> 'primary_evidence_lat')),
  NULL,
  'T8: rejected status returns MASKED (NULL) latitude'
);

SELECT * FROM finish();
ROLLBACK;
