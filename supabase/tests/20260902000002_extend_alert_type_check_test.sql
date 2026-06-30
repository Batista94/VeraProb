\set ON_ERROR_ROLLBACK 1
\set ON_ERROR_STOP true

BEGIN;
SELECT plan(9);

-- =============================================================================
-- pgTAP: 20260902000002_extend_alert_type_check — Phase 10.6
--
-- Tests:
--   C1-C5: valid_alert_type CHECK widening (new type + regression guards)
--   D1-D4: chk_alert_driver_attribution state and TELEMETRY_SILENT exemption
-- =============================================================================

-- ── Setup ─────────────────────────────────────────────────────────────────────

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.organizations LIMIT 1) THEN
    RAISE EXCEPTION 'No organization seed data; run make setup first.';
  END IF;
END $$;

CREATE TEMP TABLE _t_ids ON COMMIT DROP AS
  SELECT o.id AS org_id, c.id AS contract_id
  FROM   public.organizations o
  JOIN   public.contracts c ON c.organization_id = o.id
  LIMIT  1;

-- ── C: valid_alert_type CHECK widening ───────────────────────────────────────

-- C1: TELEMETRY_SILENT accepted (new type added by this migration)
SELECT lives_ok(
  $sql$
    INSERT INTO public.operational_alerts
      (organization_id, contract_id, entity_id, alert_type, severity, triggered_at_utc, context)
    SELECT org_id, contract_id, 'e-c1', 'TELEMETRY_SILENT', 'HIGH', now(),
           '{}'::jsonb
    FROM _t_ids
  $sql$,
  'C1: TELEMETRY_SILENT accepted by valid_alert_type CHECK'
);

-- C2: DISPUTE_DEFENSE_SUBMITTED accepted (regression — was silently dropped in
--     original migration draft when rebuilding the CHECK from scratch)
SELECT lives_ok(
  $sql$
    INSERT INTO public.operational_alerts
      (organization_id, contract_id, entity_id, alert_type, severity, triggered_at_utc, context)
    SELECT org_id, contract_id, 'e-c2', 'DISPUTE_DEFENSE_SUBMITTED', 'INFO', now(),
           '{}'::jsonb
    FROM _t_ids
  $sql$,
  'C2: DISPUTE_DEFENSE_SUBMITTED still accepted (regression check)'
);

-- C3: SLA_BREACH accepted (regression)
SELECT lives_ok(
  $sql$
    INSERT INTO public.operational_alerts
      (organization_id, contract_id, entity_id, alert_type, severity, triggered_at_utc, context)
    SELECT org_id, contract_id, 'e-c3', 'SLA_BREACH', 'HIGH', now(),
           '{"driver_id":"d-c3"}'::jsonb
    FROM _t_ids
  $sql$,
  'C3: SLA_BREACH still accepted (regression check)'
);

-- C4: POTENTIAL_TIME_FRAUD accepted (regression)
SELECT lives_ok(
  $sql$
    INSERT INTO public.operational_alerts
      (organization_id, contract_id, entity_id, alert_type, severity, triggered_at_utc, context)
    SELECT org_id, contract_id, 'e-c4', 'POTENTIAL_TIME_FRAUD', 'CRITICAL', now(),
           '{"driver_id":"d-c4"}'::jsonb
    FROM _t_ids
  $sql$,
  'C4: POTENTIAL_TIME_FRAUD still accepted (regression check)'
);

-- C5: Unrecognised type rejected by valid_alert_type CHECK
SELECT throws_ok(
  $sql$
    INSERT INTO public.operational_alerts
      (organization_id, contract_id, entity_id, alert_type, severity, triggered_at_utc, context)
    SELECT org_id, contract_id, 'e-c5', 'PHANTOM_TYPE', 'INFO', now(),
           '{}'::jsonb
    FROM _t_ids
  $sql$,
  '23514',
  NULL,
  'C5: unknown alert_type rejected by valid_alert_type CHECK (23514)'
);

-- ── D: chk_alert_driver_attribution constraint state ─────────────────────────

-- D1: constraint remains NOT VALID — intentional design (older rows predate
--     driver attribution; a VALIDATE scan would fail on them)
SELECT ok(
  NOT (
    SELECT convalidated FROM pg_constraint
    WHERE conrelid = 'public.operational_alerts'::regclass
      AND conname = 'chk_alert_driver_attribution'
  ),
  'D1: chk_alert_driver_attribution is NOT VALID (intentional — INV-DB)'
);

-- D2: TELEMETRY_SILENT exempt from driver_id requirement (new exemption in this migration)
SELECT lives_ok(
  $sql$
    INSERT INTO public.operational_alerts
      (organization_id, contract_id, entity_id, alert_type, severity, triggered_at_utc, context)
    SELECT org_id, contract_id, 'e-d2', 'TELEMETRY_SILENT', 'HIGH', now(),
           '{"device_id":"SASCAR-001"}'::jsonb
    FROM _t_ids
  $sql$,
  'D2: TELEMETRY_SILENT without driver_id accepted (new exempt type)'
);

-- D3: DISPUTE_DEFENSE_SUBMITTED still exempt from driver_id (regression)
SELECT lives_ok(
  $sql$
    INSERT INTO public.operational_alerts
      (organization_id, contract_id, entity_id, alert_type, severity, triggered_at_utc, context)
    SELECT org_id, contract_id, 'e-d3', 'DISPUTE_DEFENSE_SUBMITTED', 'INFO', now(),
           '{"portal_token":"tok-x"}'::jsonb
    FROM _t_ids
  $sql$,
  'D3: DISPUTE_DEFENSE_SUBMITTED without driver_id still accepted (regression)'
);

-- D4: driver-bound type still requires driver_id (guard not weakened)
SELECT throws_ok(
  $sql$
    INSERT INTO public.operational_alerts
      (organization_id, contract_id, entity_id, alert_type, severity, triggered_at_utc, context)
    SELECT org_id, contract_id, 'e-d4', 'DEVIATION', 'HIGH', now(),
           '{}'::jsonb
    FROM _t_ids
  $sql$,
  '23514',
  NULL,
  'D4: DEVIATION without driver_id still blocked by chk_alert_driver_attribution (23514)'
);

SELECT * FROM finish();
ROLLBACK;
