-- =============================================================================
-- Migration: Autonomous Closer (Phase 10 — Workstream A)
--
-- Part 1: Schema
--   - execution_states.destination_zone_entered_at_utc  TIMESTAMPTZ  (INV-6)
--   - sla_audit_ledger.actor_type / actor_id            (C3: system rows null actor_id)
--   - GIST index on operational_zones                   (C2: PostGIS proximity)
--   - ingestion_alerts table                            (C4: INV-10 INV-6 denial)
--
-- Part 2: check_execution_compliance(p_org_id, p_set_id) → BOOLEAN
--   Missing boolean RPC called by telegram-webhook (lines 428, 573).
--
-- Part 3: check_and_close_execution_autonomously(p_org_id, p_set_id, lat, lng) → JSONB
--   CAS-safe autonomous close using GPS proximity + dwell + evidence checklist.
--
-- INV-1: org_id filter on ALL queries.
-- INV-3: APPEND-ONLY — complete_execution appends to execution_state_transitions.
-- INV-6: TIMESTAMPTZ on destination_zone_entered_at_utc.
-- INV-10: ingestion_alerts for INV-6 violations.
-- INV-15: CAS first-write-wins on dwell entry; complete_execution handles race.
-- INV-26: wrong-org returns same JSONB as not-found.
-- =============================================================================

SET client_min_messages TO 'WARNING';

-- PostGIS required for ST_MakePoint / ST_Distance / geography casts.
CREATE EXTENSION IF NOT EXISTS postgis SCHEMA public;

-- ── Part 1: Schema ────────────────────────────────────────────────────────────

-- C3: actor columns on sla_audit_ledger (service_role calls have (auth.jwt() ->> 'sub')=NULL)
ALTER TABLE public.sla_audit_ledger
  ADD COLUMN IF NOT EXISTS actor_type TEXT DEFAULT 'system'
    CHECK (actor_type IN ('system', 'user', 'admin')),
  ADD COLUMN IF NOT EXISTS actor_id UUID;

COMMENT ON COLUMN public.sla_audit_ledger.actor_type IS
  'C3: system=RPC/cron, user=driver, admin=operator. INV-26: system rows have actor_id=NULL.';
COMMENT ON COLUMN public.sla_audit_ledger.actor_id IS
  'NULL for system-triggered rows (service_role has (auth.jwt() ->> 'sub')=NULL). INV-26.';

-- First-write-wins dwell tracker for destination zone (INV-6: TIMESTAMPTZ).
ALTER TABLE public.execution_states
  ADD COLUMN IF NOT EXISTS destination_zone_entered_at_utc TIMESTAMPTZ;

COMMENT ON COLUMN public.execution_states.destination_zone_entered_at_utc IS
  'Set once (CAS) when vehicle first enters destination zone. INV-6: TIMESTAMPTZ. INV-15: first-write-wins.';

-- C2: GIST index for PostGIS spatial queries on operational_zones.
CREATE INDEX IF NOT EXISTS idx_operational_zones_geog
  ON public.operational_zones USING GIST (
    CAST(ST_MakePoint(longitude, latitude) AS geography)
  );

-- C4: ingestion_alerts — operator-visible INV-6/INV-10 violations from ingest functions.
CREATE TABLE IF NOT EXISTS public.ingestion_alerts (
  id                   UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id      UUID        NOT NULL REFERENCES public.organizations(id),
  device_serial        TEXT,
  alert_type           TEXT        NOT NULL,
  detail               TEXT,
  created_at_utc       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  acknowledged_at_utc  TIMESTAMPTZ
);

ALTER TABLE public.ingestion_alerts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "org_isolation" ON public.ingestion_alerts
  USING ((auth.jwt() ->> 'organization_id')::UUID = organization_id);

GRANT ALL   ON public.ingestion_alerts TO service_role;
GRANT SELECT ON public.ingestion_alerts TO authenticated;

-- ── Part 2: check_execution_compliance ───────────────────────────────────────
--
-- Returns TRUE if: no REQUIRED_EVIDENCE rule, OR all required types have ≥1
-- matching row in telegram_evidence_categories for the given set_id.
-- Called from telegram-webhook after evidence tagging (post-tag callback flow).
--
-- INV-1: org_id filter on all queries.
-- INV-26: not-found returns FALSE (same as wrong-org — no inference possible).

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
  SELECT contract_id INTO v_contract_id
    FROM public.execution_states
   WHERE set_id          = p_set_id
     AND organization_id = p_org_id
   LIMIT 1;

  IF v_contract_id IS NULL THEN
    RETURN FALSE; -- not found (INV-26)
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
    RETURN TRUE; -- no requirements defined
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
  'Returns TRUE if all REQUIRED_EVIDENCE types are satisfied for the SET. INV-1, INV-26.';

-- ── Part 3: check_and_close_execution_autonomously ───────────────────────────
--
-- Logic:
--   1. Fetch execution + destination zone. Guard: status IN (inTransit, planned).
--   2. Resolve GPS: p_current_lat/lng if provided, else latest canonical_fact.
--   3. PostGIS ST_Distance for human-readable audit; ST_DWithin for proximity bool.
--   4. If outside zone → {result:'outside_dest_zone'}.
--   5. If inside zone + first entry → CAS UPDATE destination_zone_entered_at_utc.
--   6. Scenario 1 (zero evidence): dwell < 300s → dwell_pending; else → close.
--   7. Scenario 2 (evidence required): all types fulfilled → close; else → evidence_pending.
--   8. Close via complete_execution() (CAS-safe, handles race).
--   9. Append SYSTEM_AUTO_CLOSE to sla_audit_ledger (actor_type='system').
--
-- INV-1, INV-3, INV-6, INV-15, INV-26.

CREATE OR REPLACE FUNCTION public.check_and_close_execution_autonomously(
  p_org_id      UUID,
  p_set_id      TEXT,
  p_current_lat DOUBLE PRECISION DEFAULT NULL,
  p_current_lng DOUBLE PRECISION DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_exec_id     UUID;
  v_contract_id TEXT;
  v_status      TEXT;
  v_dest_zone_id UUID;
  v_vehicle_hint TEXT;
  v_entered_at  TIMESTAMPTZ;
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
  IF v_entered_at IS NULL THEN
    UPDATE public.execution_states
       SET destination_zone_entered_at_utc = NOW()
     WHERE set_id          = p_set_id
       AND organization_id = p_org_id
       AND destination_zone_entered_at_utc IS NULL;
    v_entered_at := NOW();
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

REVOKE ALL ON FUNCTION public.check_and_close_execution_autonomously(UUID, TEXT, DOUBLE PRECISION, DOUBLE PRECISION) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.check_and_close_execution_autonomously(UUID, TEXT, DOUBLE PRECISION, DOUBLE PRECISION) TO authenticated;
GRANT EXECUTE ON FUNCTION public.check_and_close_execution_autonomously(UUID, TEXT, DOUBLE PRECISION, DOUBLE PRECISION) TO service_role;

COMMENT ON FUNCTION public.check_and_close_execution_autonomously IS
  'GPS-triggered autonomous execution closer. CAS dwell/evidence gates. INV-1,3,6,15,26.';
