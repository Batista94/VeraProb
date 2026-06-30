\set ON_ERROR_ROLLBACK 1
\set ON_ERROR_STOP true

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(11);

-- ── Seeds ────────────────────────────────────────────────────────────────────
INSERT INTO public.organizations (
  id, name, legal_name, cnpj, timezone, currency_code,
  plan_type, max_vehicles, max_active_contracts, tool_cost_cents,
  dwell_time_seconds, billing_day, contact_email, external_id,
  organization_type, allowed_domains
) VALUES
  ('00000000-0000-0000-0000-000000000901', 'Alert Resolve Org A', 'Alert Resolve Org A SA',
   '00000000000901', 'America/Sao_Paulo', 'BRL', 'enterprise',
   1000, 50, 15000, 300, 15, 'oa@test.com', 'EXT_AR_09A', 'LOGISTICS', ARRAY['test.com']),
  ('00000000-0000-0000-0000-000000000902', 'Alert Resolve Org B', 'Alert Resolve Org B SA',
   '00000000000902', 'America/Sao_Paulo', 'BRL', 'enterprise',
   1000, 50, 15000, 300, 15, 'ob@test.com', 'EXT_AR_09B', 'LOGISTICS', ARRAY['test.com'])
ON CONFLICT (id) DO NOTHING;

-- Queue entries: one per test scenario.
-- ledger_entry_id is a comment-FK only (no DB constraint) — fake UUIDs are safe.
INSERT INTO public.sanction_review_queue
  (id, organization_id, ledger_entry_id, set_id, contract_id, verdict_evidence, status)
VALUES
  -- T1: pending → applied
  ('00000000-0000-0000-0000-0000000009e1', '00000000-0000-0000-0000-000000000901',
   '00000000-0000-0000-0000-0000000009f1', 'set-t1', 'ctr-t1', '{}'::jsonb, 'pending'),
  -- T2: pending → rejected
  ('00000000-0000-0000-0000-0000000009e2', '00000000-0000-0000-0000-000000000901',
   '00000000-0000-0000-0000-0000000009f2', 'set-t2', 'ctr-t2', '{}'::jsonb, 'pending'),
  -- T3: disputed → applied (both alert types)
  ('00000000-0000-0000-0000-0000000009e3', '00000000-0000-0000-0000-000000000901',
   '00000000-0000-0000-0000-0000000009f3', 'set-t3', 'ctr-t3', '{}'::jsonb, 'disputed'),
  -- T4: pending → acknowledged
  ('00000000-0000-0000-0000-0000000009e4', '00000000-0000-0000-0000-000000000901',
   '00000000-0000-0000-0000-0000000009f4', 'set-t4', 'ctr-t4', '{}'::jsonb, 'pending'),
  -- T5: pending → disputed (non-terminal, no resolve)
  ('00000000-0000-0000-0000-0000000009e5', '00000000-0000-0000-0000-000000000901',
   '00000000-0000-0000-0000-0000000009f5', 'set-t5', 'ctr-t5', '{}'::jsonb, 'pending'),
  -- T6: cross-org guard (Org A entry, Org B has alert with same set/ctr values)
  ('00000000-0000-0000-0000-0000000009e6', '00000000-0000-0000-0000-000000000901',
   '00000000-0000-0000-0000-0000000009f6', 'set-cross', 'ctr-cross', '{}'::jsonb, 'pending'),
  -- T7: already terminal at 'applied' — idempotent re-update
  ('00000000-0000-0000-0000-0000000009e7', '00000000-0000-0000-0000-000000000901',
   '00000000-0000-0000-0000-0000000009f7', 'set-t7', 'ctr-t7', '{}'::jsonb, 'applied'),
  -- T8: DISPUTE_DEFENSE_SUBMITTED only (no PENALTY_APPLIED)
  ('00000000-0000-0000-0000-0000000009e8', '00000000-0000-0000-0000-000000000901',
   '00000000-0000-0000-0000-0000000009f8', 'set-t8', 'ctr-t8', '{}'::jsonb, 'disputed');

-- Operational alerts seeded per scenario.
-- PENALTY_APPLIED requires driver_id in context (chk_alert_driver_attribution).
-- DISPUTE_DEFENSE_SUBMITTED is exempt; needs queue_entry_id for trigger match.
INSERT INTO public.operational_alerts
  (organization_id, contract_id, entity_id, alert_type, severity, triggered_at_utc, context)
VALUES
  -- T1: PENALTY_APPLIED for set-t1 / ctr-t1
  ('00000000-0000-0000-0000-000000000901', 'ctr-t1', 'set-t1',
   'PENALTY_APPLIED', 'HIGH', NOW(),
   '{"driver_id": "00000000-0000-0000-0000-0000000009d1", "total_penalty_cents": 50000}'::jsonb),
  -- T2: PENALTY_APPLIED for set-t2 / ctr-t2
  ('00000000-0000-0000-0000-000000000901', 'ctr-t2', 'set-t2',
   'PENALTY_APPLIED', 'HIGH', NOW(),
   '{"driver_id": "00000000-0000-0000-0000-0000000009d2", "total_penalty_cents": 30000}'::jsonb),
  -- T3a: PENALTY_APPLIED for set-t3 / ctr-t3 (disputed → applied)
  ('00000000-0000-0000-0000-000000000901', 'ctr-t3', 'set-t3',
   'PENALTY_APPLIED', 'HIGH', NOW(),
   '{"driver_id": "00000000-0000-0000-0000-0000000009d3", "total_penalty_cents": 80000}'::jsonb),
  -- T3b: DISPUTE_DEFENSE_SUBMITTED for queue entry e3 (disputed → applied)
  ('00000000-0000-0000-0000-000000000901', 'ctr-t3', 'set-t3',
   'DISPUTE_DEFENSE_SUBMITTED', 'HIGH', NOW(),
   '{"queue_entry_id": "00000000-0000-0000-0000-0000000009e3", "defense_type": "JUSTIFICATION_ONLY"}'::jsonb),
  -- T4: PENALTY_APPLIED for set-t4 / ctr-t4 (pending → acknowledged)
  ('00000000-0000-0000-0000-000000000901', 'ctr-t4', 'set-t4',
   'PENALTY_APPLIED', 'HIGH', NOW(),
   '{"driver_id": "00000000-0000-0000-0000-0000000009d4", "total_penalty_cents": 20000}'::jsonb),
  -- T5: PENALTY_APPLIED for set-t5 / ctr-t5 (pending → disputed, non-terminal)
  ('00000000-0000-0000-0000-000000000901', 'ctr-t5', 'set-t5',
   'PENALTY_APPLIED', 'HIGH', NOW(),
   '{"driver_id": "00000000-0000-0000-0000-0000000009d5", "total_penalty_cents": 10000}'::jsonb),
  -- T6: Org B alert with same entity/contract values as Org A entry e6
  ('00000000-0000-0000-0000-000000000902', 'ctr-cross', 'set-cross',
   'PENALTY_APPLIED', 'HIGH', NOW(),
   '{"driver_id": "00000000-0000-0000-0000-0000000009d6", "total_penalty_cents": 60000}'::jsonb),
  -- T7: PENALTY_APPLIED for set-t7 / ctr-t7 (entry already 'applied', trigger no-ops)
  ('00000000-0000-0000-0000-000000000901', 'ctr-t7', 'set-t7',
   'PENALTY_APPLIED', 'HIGH', NOW(),
   '{"driver_id": "00000000-0000-0000-0000-0000000009d7", "total_penalty_cents": 15000}'::jsonb),
  -- T8: DISPUTE_DEFENSE_SUBMITTED only for queue entry e8 (no PENALTY_APPLIED)
  ('00000000-0000-0000-0000-000000000901', 'ctr-t8', 'set-t8',
   'DISPUTE_DEFENSE_SUBMITTED', 'HIGH', NOW(),
   '{"queue_entry_id": "00000000-0000-0000-0000-0000000009e8", "defense_type": "FILE_ATTACHMENT"}'::jsonb);

-- ── T0: Structural ────────────────────────────────────────────────────────────
SELECT has_function(
  'public', 'auto_resolve_alerts_on_sanction_terminal', ARRAY[]::text[],
  'T0a: trigger function auto_resolve_alerts_on_sanction_terminal exists'
);

SELECT ok(
  EXISTS(
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'trg_srq_resolve_alerts'
      AND tgrelid = 'public.sanction_review_queue'::regclass
  ),
  'T0b: trigger trg_srq_resolve_alerts exists on sanction_review_queue'
);

-- ── T1: pending → applied resolves PENALTY_APPLIED ───────────────────────────
UPDATE public.sanction_review_queue SET status = 'applied'
WHERE id = '00000000-0000-0000-0000-0000000009e1';

SELECT is(
  (SELECT status FROM public.operational_alerts
    WHERE organization_id = '00000000-0000-0000-0000-000000000901'
      AND alert_type = 'PENALTY_APPLIED' AND entity_id = 'set-t1' AND contract_id = 'ctr-t1'),
  'RESOLVED',
  'T1: pending→applied resolves PENALTY_APPLIED alert'
);

-- ── T2: pending → rejected resolves PENALTY_APPLIED ──────────────────────────
UPDATE public.sanction_review_queue SET status = 'rejected'
WHERE id = '00000000-0000-0000-0000-0000000009e2';

SELECT is(
  (SELECT status FROM public.operational_alerts
    WHERE organization_id = '00000000-0000-0000-0000-000000000901'
      AND alert_type = 'PENALTY_APPLIED' AND entity_id = 'set-t2' AND contract_id = 'ctr-t2'),
  'RESOLVED',
  'T2: pending→rejected resolves PENALTY_APPLIED alert'
);

-- ── T3: disputed → applied resolves both alert types ─────────────────────────
UPDATE public.sanction_review_queue SET status = 'applied'
WHERE id = '00000000-0000-0000-0000-0000000009e3';

SELECT is(
  (SELECT status FROM public.operational_alerts
    WHERE organization_id = '00000000-0000-0000-0000-000000000901'
      AND alert_type = 'PENALTY_APPLIED' AND entity_id = 'set-t3' AND contract_id = 'ctr-t3'),
  'RESOLVED',
  'T3a: disputed→applied resolves PENALTY_APPLIED alert'
);

SELECT is(
  (SELECT status FROM public.operational_alerts
    WHERE organization_id = '00000000-0000-0000-0000-000000000901'
      AND alert_type = 'DISPUTE_DEFENSE_SUBMITTED'
      AND context->>'queue_entry_id' = '00000000-0000-0000-0000-0000000009e3'),
  'RESOLVED',
  'T3b: disputed→applied resolves DISPUTE_DEFENSE_SUBMITTED alert'
);

-- ── T4: pending → acknowledged resolves PENALTY_APPLIED ──────────────────────
UPDATE public.sanction_review_queue SET status = 'acknowledged'
WHERE id = '00000000-0000-0000-0000-0000000009e4';

SELECT is(
  (SELECT status FROM public.operational_alerts
    WHERE organization_id = '00000000-0000-0000-0000-000000000901'
      AND alert_type = 'PENALTY_APPLIED' AND entity_id = 'set-t4' AND contract_id = 'ctr-t4'),
  'RESOLVED',
  'T4: pending→acknowledged resolves PENALTY_APPLIED alert'
);

-- ── T5: pending → disputed (non-terminal) — alert stays ACTIVE ───────────────
UPDATE public.sanction_review_queue SET status = 'disputed'
WHERE id = '00000000-0000-0000-0000-0000000009e5';

SELECT is(
  (SELECT status FROM public.operational_alerts
    WHERE organization_id = '00000000-0000-0000-0000-000000000901'
      AND alert_type = 'PENALTY_APPLIED' AND entity_id = 'set-t5' AND contract_id = 'ctr-t5'),
  'ACTIVE',
  'T5: pending→disputed (non-terminal) leaves PENALTY_APPLIED alert ACTIVE'
);

-- ── T6: cross-org guard — Org A flip does NOT resolve Org B alert ─────────────
UPDATE public.sanction_review_queue SET status = 'applied'
WHERE id = '00000000-0000-0000-0000-0000000009e6';

SELECT is(
  (SELECT status FROM public.operational_alerts
    WHERE organization_id = '00000000-0000-0000-0000-000000000902'
      AND alert_type = 'PENALTY_APPLIED' AND entity_id = 'set-cross' AND contract_id = 'ctr-cross'),
  'ACTIVE',
  'T6: cross-org guard — Org B alert with same entity/contract stays ACTIVE (INV-22)'
);

-- ── T7: idempotency — already-terminal entry, trigger is a no-op ──────────────
-- Entry e7 starts as 'applied'. Re-updating to 'applied' → OLD.status is
-- terminal → trigger guard returns early → ACTIVE alert is untouched.
UPDATE public.sanction_review_queue SET status = 'applied'
WHERE id = '00000000-0000-0000-0000-0000000009e7';

SELECT is(
  (SELECT status FROM public.operational_alerts
    WHERE organization_id = '00000000-0000-0000-0000-000000000901'
      AND alert_type = 'PENALTY_APPLIED' AND entity_id = 'set-t7' AND contract_id = 'ctr-t7'),
  'ACTIVE',
  'T7: idempotency — re-update of already-terminal row leaves alert ACTIVE'
);

-- ── T8: DISPUTE_DEFENSE_SUBMITTED only — resolves without PENALTY_APPLIED ─────
UPDATE public.sanction_review_queue SET status = 'applied'
WHERE id = '00000000-0000-0000-0000-0000000009e8';

SELECT is(
  (SELECT status FROM public.operational_alerts
    WHERE organization_id = '00000000-0000-0000-0000-000000000901'
      AND alert_type = 'DISPUTE_DEFENSE_SUBMITTED'
      AND context->>'queue_entry_id' = '00000000-0000-0000-0000-0000000009e8'),
  'RESOLVED',
  'T8: disputed→applied resolves DISPUTE_DEFENSE_SUBMITTED when no PENALTY_APPLIED exists'
);

SELECT * FROM finish();
ROLLBACK;
