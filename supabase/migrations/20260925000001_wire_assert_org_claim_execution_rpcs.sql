-- pr_scanner: ignore-regression — PR elevation CIA migrations (Council-approved plan)
-- =============================================================================
-- Migration: Wire assert_org_claim into execution SECURITY DEFINER RPCs (PR7)
-- Depends on: 20260923000006 (assert_org_claim), 20260923000003 (closer v2)
-- Invariants: INV-1, INV-22, INV-26. INV-DB: CREATE OR REPLACE only.
-- =============================================================================

SET client_min_messages TO 'WARNING';

-- ── complete_execution ───────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.complete_execution(
  p_org_id UUID,
  p_set_id TEXT,
  p_reason TEXT DEFAULT 'GEOFENCE_AUTO_FINISH'
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_exec_id        UUID;
  v_prev_status    TEXT;
  v_rows_updated   INT;
BEGIN
  PERFORM public.assert_org_claim(p_org_id);

  SELECT id, status
    INTO v_exec_id, v_prev_status
    FROM public.execution_states
   WHERE set_id          = p_set_id
     AND organization_id = p_org_id
   LIMIT 1;

  IF v_exec_id IS NULL THEN
    RETURN FALSE;
  END IF;

  IF v_prev_status = 'completed' THEN
    RETURN FALSE;
  END IF;

  IF v_prev_status NOT IN ('inTransit', 'planned') THEN
    RETURN FALSE;
  END IF;

  UPDATE public.execution_states
     SET status                     = 'completed',
         status_last_updated_at_utc = NOW(),
         finalized_at_utc           = NOW()
   WHERE set_id          = p_set_id
     AND organization_id = p_org_id
     AND status          IN ('inTransit', 'planned');

  GET DIAGNOSTICS v_rows_updated = ROW_COUNT;

  IF v_rows_updated = 0 THEN
    RETURN FALSE;
  END IF;

  INSERT INTO public.execution_state_transitions (
    execution_state_id,
    organization_id,
    previous_status,
    new_status,
    transitioned_at_utc,
    reason,
    metadata
  ) VALUES (
    v_exec_id,
    p_org_id,
    v_prev_status,
    'completed',
    NOW(),
    p_reason,
    jsonb_build_object(
      'source',      'geofence_engine',
      'set_id',      p_set_id,
      'race_winner', TRUE
    )
  );

  RETURN TRUE;
END;
$$;

REVOKE ALL ON FUNCTION public.complete_execution(UUID, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.complete_execution(UUID, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.complete_execution(UUID, TEXT, TEXT) TO service_role;

COMMENT ON FUNCTION public.complete_execution IS
  'CAS inTransit|planned → completed. PR7: assert_org_claim at entry. INV-1,15,22,26.';

-- ── start_transit_for_execution ──────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.start_transit_for_execution(
  p_org_id UUID,
  p_set_id TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_current_status TEXT;
BEGIN
  PERFORM public.assert_org_claim(p_org_id);

  SELECT status INTO v_current_status
    FROM public.execution_states
   WHERE set_id = p_set_id
     AND organization_id = p_org_id
   LIMIT 1;

  IF v_current_status IS NULL THEN
    RETURN FALSE;
  END IF;

  IF v_current_status = 'inTransit' THEN
    RETURN TRUE;
  END IF;

  IF v_current_status != 'planned' THEN
    RETURN FALSE;
  END IF;

  UPDATE public.execution_states
     SET status                     = 'inTransit',
         status_last_updated_at_utc = NOW()
   WHERE set_id          = p_set_id
     AND organization_id = p_org_id
     AND status          = 'planned';

  INSERT INTO public.execution_state_transitions (
    execution_state_id,
    organization_id,
    previous_status,
    new_status,
    transitioned_at_utc,
    reason,
    metadata
  )
  SELECT id, organization_id, 'planned', 'inTransit', NOW(), 'TELEGRAM_START_TRANSIT',
         jsonb_build_object('source', 'telegram', 'set_id', p_set_id)
    FROM public.execution_states
   WHERE set_id = p_set_id AND organization_id = p_org_id;

  RETURN TRUE;
END;
$$;

REVOKE ALL ON FUNCTION public.start_transit_for_execution(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.start_transit_for_execution(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.start_transit_for_execution(UUID, TEXT) TO service_role;

COMMENT ON FUNCTION public.start_transit_for_execution IS
  'planned → inTransit. PR7: assert_org_claim at entry. INV-1,22,26.';

-- ── check_execution_compliance ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.check_execution_compliance(
  p_org_id UUID,
  p_set_id TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
  v_contract_id TEXT;
  v_rule_config JSONB;
  v_required    TEXT[];
  v_type        TEXT;
  v_count       INT;
BEGIN
  PERFORM public.assert_org_claim(p_org_id);

  SELECT contract_id INTO v_contract_id
    FROM public.execution_states
   WHERE set_id          = p_set_id
     AND organization_id = p_org_id
   LIMIT 1;

  IF v_contract_id IS NULL THEN
    RETURN FALSE;
  END IF;

  SELECT crv.rule_config INTO v_rule_config
    FROM public.contract_rule_sets crs
    JOIN public.contract_rule_versions crv ON crv.rule_set_id = crs.id
   WHERE crs.contract_id    = v_contract_id
     AND crs.organization_id = p_org_id
     AND crv.rule_type      = 'REQUIRED_EVIDENCE'
     AND crv.active_to_utc  IS NULL
   LIMIT 1;

  IF v_rule_config IS NULL THEN
    RETURN TRUE;
  END IF;

  SELECT ARRAY(SELECT jsonb_array_elements_text(v_rule_config -> 'types'))
    INTO v_required;

  IF v_required IS NULL OR array_length(v_required, 1) IS NULL THEN
    RETURN TRUE;
  END IF;

  FOREACH v_type IN ARRAY v_required LOOP
    SELECT COUNT(*)::INT INTO v_count
      FROM public.telegram_evidence_categories tec
      JOIN public.telegram_evidence_uploads teu ON tec.evidence_upload_id = teu.id
     WHERE teu.organization_id = p_org_id
       AND teu.linked_set_id   = p_set_id
       AND tec.category        = v_type;

    IF v_count = 0 THEN
      RETURN FALSE;
    END IF;
  END LOOP;

  RETURN TRUE;
END;
$$;

REVOKE ALL ON FUNCTION public.check_execution_compliance(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.check_execution_compliance(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.check_execution_compliance(UUID, TEXT) TO service_role;

COMMENT ON FUNCTION public.check_execution_compliance IS
  'REQUIRED_EVIDENCE gate. PR7: assert_org_claim at entry. INV-1,22,26.';

-- ── check_and_close_execution_autonomously ───────────────────────────────────
CREATE OR REPLACE FUNCTION public.check_and_close_execution_autonomously(
  p_org_id      UUID,
  p_set_id      TEXT,
  p_current_lat DOUBLE PRECISION DEFAULT NULL,
  p_current_lng DOUBLE PRECISION DEFAULT NULL,
  p_device_ts   TIMESTAMPTZ     DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_exec_id     UUID;
  v_contract_id TEXT;
  v_status      TEXT;
  v_dest_zone_id UUID;
  v_vehicle_hint TEXT;
  v_entered_at  TIMESTAMPTZ;
  v_entry_ts    TIMESTAMPTZ;
  -- Physical Metric - Double Required
  v_lat         DOUBLE PRECISION;
  -- Physical Metric - Double Required
  v_lng         DOUBLE PRECISION;
  -- Physical Metric - Double Required
  v_zone_lat    DOUBLE PRECISION;
  -- Physical Metric - Double Required
  v_zone_lng    DOUBLE PRECISION;
  v_zone_radius INTEGER;
  -- Physical Metric - Double Required
  v_dist_m      DOUBLE PRECISION;
  -- Physical Metric - Double Required
  v_dwell_secs  DOUBLE PRECISION;
  v_rule_config JSONB;
  v_required    TEXT[];
  v_type        TEXT;
  v_count       INT;
  v_fulfilled   BOOLEAN;
  v_closed      BOOLEAN;
  v_scenario    TEXT;
BEGIN
  PERFORM public.assert_org_claim(p_org_id);

  SELECT es.id, es.contract_id, es.status,
         cse.destination_zone_id,
         es.planned_vehicle_id,
         es.destination_zone_entered_at_utc
    INTO v_exec_id, v_contract_id, v_status,
         v_dest_zone_id, v_vehicle_hint, v_entered_at
    FROM public.execution_states es
    JOIN public.contractual_service_executions cse ON cse.set_id = es.set_id
   WHERE es.set_id          = p_set_id
     AND es.organization_id = p_org_id
   LIMIT 1;

  IF v_exec_id IS NULL THEN
    RETURN jsonb_build_object('result', 'not_found');
  END IF;

  IF v_status NOT IN ('inTransit', 'planned') THEN
    RETURN jsonb_build_object('result', 'closed');
  END IF;

  IF v_dest_zone_id IS NULL THEN
    RETURN jsonb_build_object('result', 'no_gps_data');
  END IF;

  v_lat := p_current_lat;
  v_lng := p_current_lng;

  IF v_lat IS NULL OR v_lng IS NULL THEN
    SELECT cf.lat, cf.lng
      INTO v_lat, v_lng
      FROM public.canonical_facts cf
      JOIN public.vehicles v ON v.id = cf.asset_id
     WHERE cf.organization_id = p_org_id
       AND (v.id::TEXT = v_vehicle_hint OR v.plate = v_vehicle_hint)
     ORDER BY cf.received_at_utc DESC
     LIMIT 1;
  END IF;

  IF v_lat IS NULL OR v_lng IS NULL THEN
    RETURN jsonb_build_object('result', 'no_gps_data');
  END IF;

  SELECT z.latitude, z.longitude, z.radius_meters
    INTO v_zone_lat, v_zone_lng, v_zone_radius
    FROM public.operational_zones z
   WHERE z.id = v_dest_zone_id
   LIMIT 1;

  IF v_zone_lat IS NULL THEN
    RETURN jsonb_build_object('result', 'no_gps_data');
  END IF;

  SELECT ST_Distance(
    ST_MakePoint(v_lng,       v_lat      )::geography,
    ST_MakePoint(v_zone_lng,  v_zone_lat )::geography
  ) INTO v_dist_m;

  IF v_dist_m > v_zone_radius THEN
    RETURN jsonb_build_object(
      'result',     'outside_dest_zone',
      'distance_m', v_dist_m,
      'radius_m',   v_zone_radius
    );
  END IF;

  IF v_entered_at IS NULL THEN
    v_entry_ts := CASE
      WHEN p_device_ts IS NOT NULL
        AND p_device_ts <= NOW()
        AND p_device_ts > NOW() - INTERVAL '2 hours'
      THEN p_device_ts
      ELSE NOW()
    END;

    UPDATE public.execution_states
       SET destination_zone_entered_at_utc = v_entry_ts
     WHERE set_id          = p_set_id
       AND organization_id = p_org_id
       AND destination_zone_entered_at_utc IS NULL;

    v_entered_at := v_entry_ts;
  END IF;

  v_dwell_secs := EXTRACT(EPOCH FROM (NOW() - v_entered_at));

  SELECT crv.rule_config INTO v_rule_config
    FROM public.contract_rule_sets crs
    JOIN public.contract_rule_versions crv ON crv.rule_set_id = crs.id
   WHERE crs.contract_id    = v_contract_id
     AND crs.organization_id = p_org_id
     AND crv.rule_type      = 'REQUIRED_EVIDENCE'
     AND crv.active_to_utc  IS NULL
   LIMIT 1;

  IF v_rule_config IS NULL THEN
    v_scenario := 'zero_evidence';
    IF v_dwell_secs < 300 THEN
      RETURN jsonb_build_object(
        'result',        'dwell_pending',
        'dwell_seconds', v_dwell_secs,
        'scenario',      v_scenario
      );
    END IF;
  ELSE
    SELECT ARRAY(SELECT jsonb_array_elements_text(v_rule_config -> 'types'))
      INTO v_required;

    IF v_required IS NULL OR array_length(v_required, 1) IS NULL THEN
      v_scenario := 'zero_evidence';
      IF v_dwell_secs < 300 THEN
        RETURN jsonb_build_object(
          'result',        'dwell_pending',
          'dwell_seconds', v_dwell_secs,
          'scenario',      v_scenario
        );
      END IF;
    ELSE
      v_scenario  := 'evidence_required';
      v_fulfilled := TRUE;

      FOREACH v_type IN ARRAY v_required LOOP
        SELECT COUNT(*)::INT INTO v_count
          FROM public.telegram_evidence_categories tec
          JOIN public.telegram_evidence_uploads teu ON tec.evidence_upload_id = teu.id
         WHERE teu.organization_id = p_org_id
           AND teu.linked_set_id   = p_set_id
           AND tec.category        = v_type;
        IF v_count = 0 THEN
          v_fulfilled := FALSE;
          EXIT;
        END IF;
      END LOOP;

      IF NOT v_fulfilled THEN
        RETURN jsonb_build_object(
          'result',        'evidence_pending',
          'dwell_seconds', v_dwell_secs,
          'scenario',      v_scenario
        );
      END IF;
    END IF;
  END IF;

  SELECT public.complete_execution(p_org_id, p_set_id, 'SYSTEM_AUTO_CLOSE')
    INTO v_closed;

  IF NOT v_closed THEN
    RETURN jsonb_build_object('result', 'closed');
  END IF;

  INSERT INTO public.sla_audit_ledger_v2 (
    organization_id, type, operator_id, set_id, contract_id, plan_version,
    payload, occurred_at_utc
  ) VALUES (
    p_org_id,
    'SYSTEM_AUTO_CLOSE',
    NULL,
    p_set_id,
    v_contract_id::uuid,
    1,
    jsonb_build_object(
      'scenario',      v_scenario,
      'dwell_seconds', v_dwell_secs,
      'distance_m',    v_dist_m,
      'device_ts_used', p_device_ts IS NOT NULL
        AND p_device_ts <= NOW()
        AND p_device_ts > NOW() - INTERVAL '2 hours',
      'triggered_by',  'autonomous_closer_rpc',
      'actor_type',    'system',
      'actor_id',      NULL
    ),
    NOW()
  );

  RETURN jsonb_build_object(
    'result',        'closed',
    'scenario',      v_scenario,
    'dwell_seconds', v_dwell_secs,
    'distance_m',    v_dist_m
  );
END;
$$;

REVOKE ALL  ON FUNCTION public.check_and_close_execution_autonomously(UUID, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, TIMESTAMPTZ) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.check_and_close_execution_autonomously(UUID, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, TIMESTAMPTZ) TO authenticated;
GRANT EXECUTE ON FUNCTION public.check_and_close_execution_autonomously(UUID, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, TIMESTAMPTZ) TO service_role;

COMMENT ON FUNCTION public.check_and_close_execution_autonomously IS
  'GPS autonomous closer. PR7: assert_org_claim at entry. Ledger → v2. INV-1,3,6,15,22,26.';
