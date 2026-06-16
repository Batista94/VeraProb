\set ON_ERROR_ROLLBACK 1
\set ON_ERROR_STOP true

BEGIN;
SELECT plan(15);

-- ── Setup ─────────────────────────────────────────────────────────────────────
-- Use existing org/contract from seed; fall back to inserting minimal fixture.
DO $$
DECLARE
  v_org_id UUID;
  v_contract_id UUID;
BEGIN
  SELECT id INTO v_org_id FROM public.organizations LIMIT 1;
  IF v_org_id IS NULL THEN
    RAISE EXCEPTION 'No organization seed data; run make setup first.';
  END IF;
END $$;

-- ── T1: Constraint exists and is NOT VALID ────────────────────────────────────
SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.operational_alerts'::regclass
      AND conname = 'chk_alert_driver_attribution'
  ),
  'T1: constraint chk_alert_driver_attribution exists'
);

SELECT ok(
  NOT (
    SELECT convalidated FROM pg_constraint
    WHERE conrelid = 'public.operational_alerts'::regclass
      AND conname = 'chk_alert_driver_attribution'
  ),
  'T1b: constraint is NOT VALID (no historical row scan)'
);

-- ── Helpers ───────────────────────────────────────────────────────────────────
-- Minimal valid insert: grab real org + contract ids.
CREATE TEMP TABLE _t_ids ON COMMIT DROP AS
  SELECT o.id AS org_id,
         c.id AS contract_id
  FROM   public.organizations o
  JOIN   public.contracts c ON c.organization_id = o.id
  LIMIT  1;

-- T2: Valid driver-bound alert WITH driver_id succeeds
SELECT lives_ok(
  $sql$
    INSERT INTO public.operational_alerts
      (organization_id, contract_id, entity_id, alert_type, severity, triggered_at_utc, context)
    SELECT org_id, contract_id, 'entity-test', 'NO_SHOW', 'CRITICAL', now(),
           '{"driver_id": "driver-abc", "window_start": "2026-01-01"}'::jsonb
    FROM   _t_ids
  $sql$,
  'T2: driver-bound alert with valid driver_id inserts OK'
);

-- T3: driver_id empty string → constraint violation (23514)
SELECT throws_ok(
  $sql$
    INSERT INTO public.operational_alerts
      (organization_id, contract_id, entity_id, alert_type, severity, triggered_at_utc, context)
    SELECT org_id, contract_id, 'entity-test', 'NO_SHOW', 'CRITICAL', now(),
           '{"driver_id": ""}'::jsonb
    FROM   _t_ids
  $sql$,
  '23514',
  NULL,
  'T3: empty driver_id blocked by constraint (23514)'
);

-- T4: driver_id JSON null → constraint violation
SELECT throws_ok(
  $sql$
    INSERT INTO public.operational_alerts
      (organization_id, contract_id, entity_id, alert_type, severity, triggered_at_utc, context)
    SELECT org_id, contract_id, 'entity-test', 'EVIDENCE_GAP', 'WARNING', now(),
           '{"driver_id": null}'::jsonb
    FROM   _t_ids
  $sql$,
  '23514',
  NULL,
  'T4: null JSON driver_id blocked by constraint (23514)'
);

-- T5: missing driver_id key entirely → constraint violation
SELECT throws_ok(
  $sql$
    INSERT INTO public.operational_alerts
      (organization_id, contract_id, entity_id, alert_type, severity, triggered_at_utc, context)
    SELECT org_id, contract_id, 'entity-test', 'PENALTY_APPLIED', 'HIGH', now(),
           '{"total_penalty_cents": 1500}'::jsonb
    FROM   _t_ids
  $sql$,
  '23514',
  NULL,
  'T5: missing driver_id key blocked by constraint (23514)'
);

-- T6: TELEGRAM_ORPHAN without driver_id → allowed
SELECT lives_ok(
  $sql$
    INSERT INTO public.operational_alerts
      (organization_id, contract_id, entity_id, alert_type, severity, triggered_at_utc, context)
    SELECT org_id, contract_id, 'entity-test', 'TELEGRAM_ORPHAN', 'WARNING', now(),
           '{"message_id": "tg-999"}'::jsonb
    FROM   _t_ids
  $sql$,
  'T6: TELEGRAM_ORPHAN without driver_id allowed (exempt)'
);

-- T7: TELEGRAM_ORPHAN with driver_id → also allowed
SELECT lives_ok(
  $sql$
    INSERT INTO public.operational_alerts
      (organization_id, contract_id, entity_id, alert_type, severity, triggered_at_utc, context)
    SELECT org_id, contract_id, 'entity-test', 'TELEGRAM_ORPHAN', 'INFO', now(),
           '{"driver_id": "driver-xyz", "message_id": "tg-998"}'::jsonb
    FROM   _t_ids
  $sql$,
  'T7: TELEGRAM_ORPHAN with driver_id also allowed'
);

-- T8-T13: all six driver-bound types blocked without driver_id
SELECT throws_ok(
  $sql$
    INSERT INTO public.operational_alerts
      (organization_id, contract_id, entity_id, alert_type, severity, triggered_at_utc, context)
    SELECT org_id, contract_id, 'entity-test', 'DEVIATION', 'HIGH', now(),
           '{"rule_id": "r1"}'::jsonb
    FROM   _t_ids
  $sql$,
  '23514',
  NULL,
  'T8: DEVIATION without driver_id blocked'
);

SELECT throws_ok(
  $sql$
    INSERT INTO public.operational_alerts
      (organization_id, contract_id, entity_id, alert_type, severity, triggered_at_utc, context)
    SELECT org_id, contract_id, 'entity-test', 'SLA_BREACH', 'HIGH', now(),
           '{}'::jsonb
    FROM   _t_ids
  $sql$,
  '23514',
  NULL,
  'T9: SLA_BREACH without driver_id blocked'
);

SELECT throws_ok(
  $sql$
    INSERT INTO public.operational_alerts
      (organization_id, contract_id, entity_id, alert_type, severity, triggered_at_utc, context)
    SELECT org_id, contract_id, 'entity-test', 'POTENTIAL_TIME_FRAUD', 'CRITICAL', now(),
           '{}'::jsonb
    FROM   _t_ids
  $sql$,
  '23514',
  NULL,
  'T10: POTENTIAL_TIME_FRAUD without driver_id blocked'
);

SELECT throws_ok(
  $sql$
    INSERT INTO public.operational_alerts
      (organization_id, contract_id, entity_id, alert_type, severity, triggered_at_utc, context)
    SELECT org_id, contract_id, 'entity-test', 'NO_SHOW', 'CRITICAL', now(),
           '{}'::jsonb
    FROM   _t_ids
  $sql$,
  '23514',
  NULL,
  'T11: NO_SHOW without driver_id blocked'
);

SELECT throws_ok(
  $sql$
    INSERT INTO public.operational_alerts
      (organization_id, contract_id, entity_id, alert_type, severity, triggered_at_utc, context)
    SELECT org_id, contract_id, 'entity-test', 'EVIDENCE_GAP', 'WARNING', now(),
           '{}'::jsonb
    FROM   _t_ids
  $sql$,
  '23514',
  NULL,
  'T12: EVIDENCE_GAP without driver_id blocked'
);

SELECT throws_ok(
  $sql$
    INSERT INTO public.operational_alerts
      (organization_id, contract_id, entity_id, alert_type, severity, triggered_at_utc, context)
    SELECT org_id, contract_id, 'entity-test', 'PENALTY_APPLIED', 'HIGH', now(),
           '{}'::jsonb
    FROM   _t_ids
  $sql$,
  '23514',
  NULL,
  'T13: PENALTY_APPLIED without driver_id blocked'
);

-- T14: whitespace-only driver_id passes DB constraint (app layer enforces UUID format)
-- The CHECK only rejects NULL and empty-string; non-empty strings (even spaces) satisfy it.
-- Real driver_ids are UUIDs sourced from bound_operator_id — this edge case cannot
-- originate from the legitimate AlertDerivationService path.
SELECT lives_ok(
  $sql$
    INSERT INTO public.operational_alerts
      (organization_id, contract_id, entity_id, alert_type, severity, triggered_at_utc, context)
    SELECT org_id, contract_id, 'entity-test', 'NO_SHOW', 'CRITICAL', now(),
           '{"driver_id": "   "}'::jsonb
    FROM   _t_ids
  $sql$,
  'T14: whitespace-only driver_id passes DB constraint (app layer guards UUID format)'
);

SELECT * FROM finish();
ROLLBACK;
