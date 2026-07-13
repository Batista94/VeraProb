-- pr_scanner: ignore-regression — PR elevation CIA migrations (Council-approved plan)
-- =============================================================================
-- Migration: assert_org_claim on process_gps + SYSTEM_AUTO_START runtime CIA
-- Depends on: 20260924000001 (process_gps v2), 20260923000006 (assert_org_claim)
-- service_role / null JWT bypass assert_org_claim — safe for ingest path.
-- Invariants: INV-1, INV-3, INV-22. INV-DB: CREATE OR REPLACE only.
-- =============================================================================

SET client_min_messages TO 'WARNING';

CREATE OR REPLACE FUNCTION public.process_gps_for_execution_transitions(
  p_org_id        UUID,
  p_device_serial TEXT,
  p_lat           DOUBLE PRECISION,
  p_lng           DOUBLE PRECISION,
  p_device_ts     TIMESTAMPTZ DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_vehicle_id     UUID;
  v_plate          TEXT;
  v_set_id         TEXT;
  v_contract_id    TEXT;
  v_status         TEXT;
  v_origin_zone_id UUID;
  -- Physical Metric - Double Required
  v_oz_lat         DOUBLE PRECISION;
  -- Physical Metric - Double Required
  v_oz_lng         DOUBLE PRECISION;
  v_oz_radius      INTEGER;
  v_started        BOOLEAN;
  v_close_result   JSONB;
BEGIN
  PERFORM public.assert_org_claim(p_org_id);

  SELECT id, plate INTO v_vehicle_id, v_plate
    FROM public.vehicles
   WHERE organization_id = p_org_id
     AND device_serial   = p_device_serial
   LIMIT 1;

  IF v_vehicle_id IS NULL THEN
    RETURN jsonb_build_object('result', 'no_asset');
  END IF;

  SELECT es.set_id, es.contract_id, es.status, cse.origin_zone_id
    INTO v_set_id, v_contract_id, v_status, v_origin_zone_id
    FROM public.execution_states es
    JOIN public.contractual_service_executions cse ON cse.set_id = es.set_id
   WHERE es.organization_id = p_org_id
     AND es.status IN ('planned', 'inTransit')
     AND (es.planned_vehicle_id = v_vehicle_id::TEXT OR es.planned_vehicle_id = v_plate)
     AND es.window_start_utc::DATE = CURRENT_DATE
   ORDER BY es.window_start_utc ASC
   LIMIT 1;

  IF v_set_id IS NULL THEN
    RETURN jsonb_build_object('result', 'none');
  END IF;

  IF v_status = 'planned' AND v_origin_zone_id IS NOT NULL THEN
    SELECT z.latitude, z.longitude, z.radius_meters
      INTO v_oz_lat, v_oz_lng, v_oz_radius
      FROM public.operational_zones z
     WHERE z.id = v_origin_zone_id
     LIMIT 1;

    IF v_oz_lat IS NOT NULL AND ST_DWithin(
      ST_MakePoint(p_lng, p_lat)::geography,
      ST_MakePoint(v_oz_lng, v_oz_lat)::geography,
      v_oz_radius
    ) THEN
      SELECT public.start_transit_for_execution(p_org_id, v_set_id) INTO v_started;

      IF v_started THEN
        INSERT INTO public.sla_audit_ledger_v2 (
          organization_id, type, operator_id, set_id, contract_id, plan_version,
          payload, occurred_at_utc
        ) VALUES (
          p_org_id,
          'SYSTEM_AUTO_START',
          NULL,
          v_set_id,
          v_contract_id::uuid,
          1,
          jsonb_build_object(
            'device_serial', p_device_serial,
            'triggered_by',  'process_gps_for_execution_transitions',
            'actor_type',    'system',
            'actor_id',      NULL
          ),
          NOW()
        );

        RETURN jsonb_build_object('result', 'started', 'set_id', v_set_id);
      END IF;
    END IF;

    RETURN jsonb_build_object('result', 'none');
  END IF;

  IF v_status = 'inTransit' THEN
    SELECT public.check_and_close_execution_autonomously(p_org_id, v_set_id, p_lat, p_lng, p_device_ts)
      INTO v_close_result;
    RETURN v_close_result;
  END IF;

  RETURN jsonb_build_object('result', 'none');
END;
$$;

REVOKE ALL ON FUNCTION public.process_gps_for_execution_transitions(UUID, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, TIMESTAMPTZ) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.process_gps_for_execution_transitions(UUID, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, TIMESTAMPTZ) TO service_role;

COMMENT ON FUNCTION public.process_gps_for_execution_transitions IS
  'GPS-driven FSM. PR7b: assert_org_claim (service_role bypass). SYSTEM_AUTO_START → v2. INV-1,3,6,15,22.';
