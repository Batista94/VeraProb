-- =============================================================================
-- Migration: Auto-Start GPS (Phase 10 — Workstream C)
--
-- Part 1: Schema
--   - vehicles.device_serial TEXT  (maps hardware serial to vehicle row)
--   - idx_vehicles_org_device_serial  (fast lookup from ingest Edge Functions)
--
-- Part 2: process_gps_for_execution_transitions(p_org_id, p_device_serial, p_lat, p_lng)
--   Called from ingest-sascar + ingest-omnitracs after each accepted canonical_fact.
--   - planned + GPS in origin zone  → start_transit_for_execution (auto-start)
--   - inTransit + GPS               → check_and_close_execution_autonomously
--
-- INV-1: org_id filter on ALL queries.
-- INV-3: APPEND-ONLY audit insert in sla_audit_ledger.
-- INV-6: TIMESTAMPTZ used throughout (INV-15: deterministic).
-- INV-22: service_role ONLY — never called directly from app.
-- =============================================================================

SET client_min_messages TO 'WARNING';

-- ── Part 1: Schema ────────────────────────────────────────────────────────────

ALTER TABLE public.vehicles
  ADD COLUMN IF NOT EXISTS device_serial TEXT;

COMMENT ON COLUMN public.vehicles.device_serial IS
  'Hardware serial from Sascar/Omnitracs payload (device_serial / unitId). Nullable: devices may predate registration. INV-8: org_id scoped via RLS.';

CREATE INDEX IF NOT EXISTS idx_vehicles_org_device_serial
  ON public.vehicles (organization_id, device_serial)
  WHERE device_serial IS NOT NULL;

-- ── Part 2: process_gps_for_execution_transitions ────────────────────────────
--
-- Called from ingest Edge Functions with each new canonical_fact (C1: EdgeRuntime.waitUntil).
-- Returns JSONB describing the transition attempted.
--
-- Flow:
--   1. Resolve vehicle from device_serial (org-scoped).
--   2. Find today's planned/inTransit execution bound to this vehicle.
--   3. Auto-Start: planned + within origin zone → start_transit_for_execution + audit.
--   4. Auto-Close: inTransit → check_and_close_execution_autonomously (delegates).
--
-- GRANT: service_role ONLY (called from ingest Edge Functions; not app-facing).

CREATE OR REPLACE FUNCTION public.process_gps_for_execution_transitions(
  p_org_id        UUID,
  p_device_serial TEXT,
  p_lat           DOUBLE PRECISION,
  p_lng           DOUBLE PRECISION
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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

  -- Step 4: auto-close (inTransit → delegate to autonomous closer)
  IF v_status = 'inTransit' THEN
    SELECT public.check_and_close_execution_autonomously(p_org_id, v_set_id, p_lat, p_lng)
      INTO v_close_result;
    RETURN v_close_result;
  END IF;

  RETURN jsonb_build_object('result', 'none');
END;
$$;

-- service_role only — ingest functions never run as authenticated
REVOKE ALL ON FUNCTION public.process_gps_for_execution_transitions(UUID, TEXT, DOUBLE PRECISION, DOUBLE PRECISION) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.process_gps_for_execution_transitions(UUID, TEXT, DOUBLE PRECISION, DOUBLE PRECISION) TO service_role;

COMMENT ON FUNCTION public.process_gps_for_execution_transitions IS
  'GPS-driven FSM: device_serial → vehicle → execution. Auto-start (planned+origin) or auto-close (inTransit+dest). INV-1,3,6,15,22.';
