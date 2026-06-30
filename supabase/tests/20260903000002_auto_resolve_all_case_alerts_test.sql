\set ON_ERROR_ROLLBACK 1
\set ON_ERROR_STOP true

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(5);

-- ── Seeds ────────────────────────────────────────────────────────────────────
INSERT INTO public.organizations (
  id, name, legal_name, cnpj, timezone, currency_code,
  plan_type, max_vehicles, max_active_contracts, tool_cost_cents,
  dwell_time_seconds, billing_day, contact_email, external_id,
  organization_type, allowed_domains
) VALUES
  ('00000000-0000-0000-0000-000000000903', 'Alert All Types Org', 'Alert All Types Org SA',
   '00000000000903', 'America/Sao_Paulo', 'BRL', 'enterprise',
   1000, 50, 15000, 300, 15, 'oc@test.com', 'EXT_AR_09C', 'LOGISTICS', ARRAY['test.com'])
ON CONFLICT (id) DO NOTHING;

-- Queue entries
INSERT INTO public.sanction_review_queue
  (id, organization_id, ledger_entry_id, set_id, contract_id, verdict_evidence, status)
VALUES
  -- T1: pending → applied (has NO_SHOW)
  ('00000000-0000-0000-0000-000000000ae1', '00000000-0000-0000-0000-000000000903',
   '00000000-0000-0000-0000-000000000af1', 'set-a1', 'ctr-a1', '{}'::jsonb, 'pending'),
  -- T2: pending → applied (has EVIDENCE_GAP)
  ('00000000-0000-0000-0000-000000000ae2', '00000000-0000-0000-0000-000000000903',
   '00000000-0000-0000-0000-000000000af2', 'set-a2', 'ctr-a2', '{}'::jsonb, 'pending'),
  -- T3: pending → applied (has NO_SHOW + EVIDENCE_GAP + PENALTY_APPLIED, all same case)
  ('00000000-0000-0000-0000-000000000ae3', '00000000-0000-0000-0000-000000000903',
   '00000000-0000-0000-0000-000000000af3', 'set-a3', 'ctr-a3', '{}'::jsonb, 'pending'),
  -- T4: pending → disputed (non-terminal, NO_SHOW must stay ACTIVE)
  ('00000000-0000-0000-0000-000000000ae4', '00000000-0000-0000-0000-000000000903',
   '00000000-0000-0000-0000-000000000af4', 'set-a4', 'ctr-a4', '{}'::jsonb, 'pending');

-- Operational alerts
INSERT INTO public.operational_alerts
  (organization_id, contract_id, entity_id, alert_type, severity, triggered_at_utc, context)
VALUES
  -- T1: NO_SHOW for set-a1 / ctr-a1
  ('00000000-0000-0000-0000-000000000903', 'ctr-a1', 'set-a1',
   'NO_SHOW', 'HIGH', NOW(),
   '{"driver_id": "00000000-0000-0000-0000-000000000ad1"}'::jsonb),
  -- T2: EVIDENCE_GAP for set-a2 / ctr-a2
  ('00000000-0000-0000-0000-000000000903', 'ctr-a2', 'set-a2',
   'EVIDENCE_GAP', 'MEDIUM', NOW(),
   '{"driver_id": "00000000-0000-0000-0000-000000000ad2"}'::jsonb),
  -- T3: three alert types for same case
  ('00000000-0000-0000-0000-000000000903', 'ctr-a3', 'set-a3',
   'NO_SHOW', 'HIGH', NOW(),
   '{"driver_id": "00000000-0000-0000-0000-000000000ad3"}'::jsonb),
  ('00000000-0000-0000-0000-000000000903', 'ctr-a3', 'set-a3',
   'EVIDENCE_GAP', 'MEDIUM', NOW(),
   '{"driver_id": "00000000-0000-0000-0000-000000000ad3"}'::jsonb),
  ('00000000-0000-0000-0000-000000000903', 'ctr-a3', 'set-a3',
   'PENALTY_APPLIED', 'HIGH', NOW(),
   '{"driver_id": "00000000-0000-0000-0000-000000000ad3", "total_penalty_cents": 45000}'::jsonb),
  -- T4: NO_SHOW for set-a4 / ctr-a4 (must stay ACTIVE after non-terminal transition)
  ('00000000-0000-0000-0000-000000000903', 'ctr-a4', 'set-a4',
   'NO_SHOW', 'HIGH', NOW(),
   '{"driver_id": "00000000-0000-0000-0000-000000000ad4"}'::jsonb);

-- ── T0: Structural ────────────────────────────────────────────────────────────
SELECT has_function(
  'public', 'auto_resolve_alerts_on_sanction_terminal', ARRAY[]::text[],
  'T0: trigger function auto_resolve_alerts_on_sanction_terminal exists'
);

-- ── T1: NO_SHOW resolves on terminal ─────────────────────────────────────────
UPDATE public.sanction_review_queue SET status = 'applied'
WHERE id = '00000000-0000-0000-0000-000000000ae1';

SELECT is(
  (SELECT status FROM public.operational_alerts
    WHERE organization_id = '00000000-0000-0000-0000-000000000903'
      AND alert_type = 'NO_SHOW' AND entity_id = 'set-a1' AND contract_id = 'ctr-a1'),
  'RESOLVED',
  'T1: pending→applied resolves NO_SHOW alert'
);

-- ── T2: EVIDENCE_GAP resolves on terminal ────────────────────────────────────
UPDATE public.sanction_review_queue SET status = 'applied'
WHERE id = '00000000-0000-0000-0000-000000000ae2';

SELECT is(
  (SELECT status FROM public.operational_alerts
    WHERE organization_id = '00000000-0000-0000-0000-000000000903'
      AND alert_type = 'EVIDENCE_GAP' AND entity_id = 'set-a2' AND contract_id = 'ctr-a2'),
  'RESOLVED',
  'T2: pending→applied resolves EVIDENCE_GAP alert'
);

-- ── T3: All three types resolve together ─────────────────────────────────────
UPDATE public.sanction_review_queue SET status = 'applied'
WHERE id = '00000000-0000-0000-0000-000000000ae3';

SELECT is(
  (SELECT COUNT(*) FROM public.operational_alerts
    WHERE organization_id = '00000000-0000-0000-0000-000000000903'
      AND entity_id = 'set-a3' AND contract_id = 'ctr-a3'
      AND status = 'RESOLVED'),
  3::bigint,
  'T3: pending→applied resolves NO_SHOW + EVIDENCE_GAP + PENALTY_APPLIED together'
);

-- ── T4: non-terminal transition leaves NO_SHOW ACTIVE ────────────────────────
UPDATE public.sanction_review_queue SET status = 'disputed'
WHERE id = '00000000-0000-0000-0000-000000000ae4';

SELECT is(
  (SELECT status FROM public.operational_alerts
    WHERE organization_id = '00000000-0000-0000-0000-000000000903'
      AND alert_type = 'NO_SHOW' AND entity_id = 'set-a4' AND contract_id = 'ctr-a4'),
  'ACTIVE',
  'T4: pending→disputed (non-terminal) leaves NO_SHOW alert ACTIVE'
);

SELECT * FROM finish();
ROLLBACK;
