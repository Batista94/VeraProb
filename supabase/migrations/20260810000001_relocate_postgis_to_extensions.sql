-- =============================================================================
-- Migration: Relocate PostGIS consumption to the `extensions` schema
--
-- Advisory remediation: `rls_disabled_in_public` on public.spatial_ref_sys.
--
-- ROOT CAUSE: 20260704000001_autonomous_closer.sql:27 installed PostGIS into the
-- `public` schema (`CREATE EXTENSION ... SCHEMA public`). This places the PostGIS
-- catalog tables (spatial_ref_sys, geometry_columns, geography_columns) inside the
-- PostgREST-exposed application schema, widening the anon attack surface and
-- leaking extension internals into the API namespace (INV-14).
--
-- The physical relocation (DROP + CREATE EXTENSION postgis SCHEMA extensions) is
-- PLATFORM-GATED: the extension is owned by `supabase_admin`, and `postgres`
-- (migration role) is non-superuser/non-owner. It MUST be performed out-of-band by
-- Supabase support / supabase_admin. See:
--   forensic_records/plans/20260810000001_relocate_postgis_to_extensions_test_plan.md
--   forensic_records/plans/20260810000002_spatial_ref_sys_accept_risk_record.md
--
-- THIS forward migration is the application-side counterpart, staged to apply in the
-- SAME maintenance window IMMEDIATELY AFTER supabase_admin relocates the extension.
-- It is idempotent and safe to apply even while PostGIS is still in `public`:
--   - The only behavioural change is widening each RPC's search_path to include
--     `extensions`, so unqualified ST_* calls resolve regardless of the extension's
--     schema. Call sites stay unqualified (matches the uuid-ossp/pgcrypto pattern in
--     20200101000000_enable_extensions.sql) so the SQL is portable.
--   - The GIST index is recreated (DROP EXTENSION ... CASCADE removes it; no table
--     uses geometry/geography columns, so there is zero data loss).
--
-- Invariants: INV-1, INV-2, INV-3, INV-6, INV-13, INV-14, INV-15, INV-22, INV-26.
-- Function bodies below are byte-identical to the live deployed definitions
-- (source of truth: 20260704000003_backdating_support.sql); the ONLY change is the
-- `SET search_path` header (`public` -> `public, extensions`).
-- =============================================================================

SET client_min_messages TO 'WARNING';

-- ── C2: GIST index for PostGIS spatial queries on operational_zones ──────────
-- Recreated because DROP EXTENSION ... CASCADE drops the index (its expression
-- depends on the geography type). operational_zones is a low-write config table.
CREATE INDEX IF NOT EXISTS idx_operational_zones_geog
  ON public.operational_zones USING GIST (
    CAST(ST_MakePoint(longitude, latitude) AS geography)
  );

-- ── check_and_close_execution_autonomously (5-param) ─────────────────────────
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
  -- Step 1: fetch execution + zone refs (INV-1, INV-26)
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
    RETURN jsonb_build_object('result', 'not_found'); -- INV-26
  END IF;

  IF v_status NOT IN ('inTransit', 'planned') THEN
    RETURN jsonb_build_object('result', 'closed'); -- terminal state
  END IF;

  IF v_dest_zone_id IS NULL THEN
    RETURN jsonb_build_object('result', 'no_gps_data');
  END IF;

  -- Step 2: resolve GPS
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

  -- Step 3: fetch destination zone geometry
  SELECT z.latitude, z.longitude, z.radius_meters
    INTO v_zone_lat, v_zone_lng, v_zone_radius
    FROM public.operational_zones z
   WHERE z.id = v_dest_zone_id
   LIMIT 1;

  IF v_zone_lat IS NULL THEN
    RETURN jsonb_build_object('result', 'no_gps_data');
  END IF;

  -- C2: PostGIS distance (GIST index: idx_operational_zones_geog)
  SELECT ST_Distance(
    ST_MakePoint(v_lng,       v_lat      )::geography,
    ST_MakePoint(v_zone_lng,  v_zone_lat )::geography
  ) INTO v_dist_m;

  -- Step 4: proximity check
  IF v_dist_m > v_zone_radius THEN
    RETURN jsonb_build_object(
      'result',     'outside_dest_zone',
      'distance_m', v_dist_m,
      'radius_m',   v_zone_radius
    );
  END IF;

  -- Step 5: first-entry CAS (INV-15: first-write-wins)
  -- INV-6: prefer p_device_ts within 2h anti-spoof window (Temporal Sovereignty)
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

  -- Step 6/7: compliance gate
  SELECT crv.rule_config INTO v_rule_config
    FROM public.contract_rule_sets crs
    JOIN public.contract_rule_versions crv ON crv.rule_set_id = crs.id
   WHERE crs.contract_id    = v_contract_id
     AND crs.organization_id = p_org_id
     AND crv.rule_type      = 'REQUIRED_EVIDENCE'
     AND crv.active_to_utc  IS NULL
   LIMIT 1;

  IF v_rule_config IS NULL THEN
    -- Scenario 1: zero evidence required (Viação) — dwell gate 300s
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
      -- Empty types array treated as zero evidence
      v_scenario := 'zero_evidence';
      IF v_dwell_secs < 300 THEN
        RETURN jsonb_build_object(
          'result',        'dwell_pending',
          'dwell_seconds', v_dwell_secs,
          'scenario',      v_scenario
        );
      END IF;
    ELSE
      -- Scenario 2: evidence required (Carga)
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

  -- Step 8: close (CAS via complete_execution — race-safe, INV-15)
  SELECT public.complete_execution(p_org_id, p_set_id, 'SYSTEM_AUTO_CLOSE')
    INTO v_closed;

  IF NOT v_closed THEN
    -- Race lost: another caller closed concurrently
    RETURN jsonb_build_object('result', 'closed');
  END IF;

  -- Step 9: INV-3 audit (C3: actor_type='system', actor_id=NULL)
  INSERT INTO public.sla_audit_ledger (
    type, set_id, contract_id, plan_version, payload, occurred_at_utc,
    actor_type, actor_id
  ) VALUES (
    'SYSTEM_AUTO_CLOSE',
    p_set_id,
    v_contract_id,
    1,
    jsonb_build_object(
      'scenario',      v_scenario,
      'dwell_seconds', v_dwell_secs,
      'distance_m',    v_dist_m,
      'device_ts_used', p_device_ts IS NOT NULL
        AND p_device_ts <= NOW()
        AND p_device_ts > NOW() - INTERVAL '2 hours',
      'triggered_by',  'autonomous_closer_rpc'
    ),
    NOW(),
    'system',
    NULL
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
  'GPS-triggered autonomous closer. 2-hour INV-6 backdating window for device_ts. CAS dwell/evidence gates. search_path includes extensions for PostGIS relocation. INV-1,3,6,15,26.';

-- ── process_gps_for_execution_transitions (5-param) ──────────────────────────
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
  -- Step 1: resolve vehicle (INV-1: org_id scoped, INV-8)
  SELECT id, plate INTO v_vehicle_id, v_plate
    FROM public.vehicles
   WHERE organization_id = p_org_id
     AND device_serial   = p_device_serial
   LIMIT 1;

  IF v_vehicle_id IS NULL THEN
    RETURN jsonb_build_object('result', 'no_asset');
  END IF;

  -- Step 2: find active execution for vehicle today
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

  -- Step 3: auto-start (planned → inTransit when inside origin zone)
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
        -- INV-3: APPEND-ONLY audit (C3: actor_type='system', actor_id=NULL)
        INSERT INTO public.sla_audit_ledger (
          type, set_id, contract_id, plan_version, payload, occurred_at_utc,
          actor_type, actor_id
        ) VALUES (
          'SYSTEM_AUTO_START',
          v_set_id,
          v_contract_id,
          1,
          jsonb_build_object(
            'device_serial', p_device_serial,
            'triggered_by',  'process_gps_for_execution_transitions'
          ),
          NOW(),
          'system',
          NULL
        );

        RETURN jsonb_build_object('result', 'started', 'set_id', v_set_id);
      END IF;
    END IF;

    -- Outside origin zone or start failed — no transition
    RETURN jsonb_build_object('result', 'none');
  END IF;

  -- Step 4: auto-close (inTransit → delegate, passing device_ts for backdating)
  IF v_status = 'inTransit' THEN
    SELECT public.check_and_close_execution_autonomously(p_org_id, v_set_id, p_lat, p_lng, p_device_ts)
      INTO v_close_result;
    RETURN v_close_result;
  END IF;

  RETURN jsonb_build_object('result', 'none');
END;
$$;

-- service_role only — ingest functions never run as authenticated
REVOKE ALL  ON FUNCTION public.process_gps_for_execution_transitions(UUID, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, TIMESTAMPTZ) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.process_gps_for_execution_transitions(UUID, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, TIMESTAMPTZ) TO service_role;

COMMENT ON FUNCTION public.process_gps_for_execution_transitions IS
  'GPS-driven FSM: device_serial → vehicle → execution. Auto-start or auto-close. search_path includes extensions for PostGIS relocation. Passes p_device_ts for INV-6 backdating. INV-1,3,6,15,22.';
