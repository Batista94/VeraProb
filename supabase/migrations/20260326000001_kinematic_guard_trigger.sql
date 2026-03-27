-- Migration: INV-17 — Kinematic Guard (database-level enforcement)
-- Phase 9.6.1: Validates v = Δd / Δt between consecutive canonical_facts.
-- Flags impossible GPS jumps as KINEMATIC_ANOMALY — does NOT reject inserts.
--
-- Dual-layer enforcement:
--   Layer 1 (authoritative): This BEFORE INSERT trigger on canonical_facts.
--   Layer 2 (client-side TDD): KinematicGuard domain service in Dart.
--
-- Uses existing index: idx_canonical_facts_asset_timeline
--   ON canonical_facts(organization_id, asset_id, gps_timestamp ASC)

-- ═══════════════════════════════════════════════════════════════════════════════
-- FUNCTION: vp_haversine_meters(lat1, lon1, lat2, lon2) → DOUBLE PRECISION
-- Pure Haversine formula returning distance in metres.
-- IMMUTABLE STRICT PARALLEL SAFE — safe for index expressions and parallel plans.
-- ═══════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.vp_haversine_meters(
  lat1 DOUBLE PRECISION,
  lon1 DOUBLE PRECISION,
  lat2 DOUBLE PRECISION,
  lon2 DOUBLE PRECISION
)
RETURNS DOUBLE PRECISION
LANGUAGE sql
IMMUTABLE STRICT PARALLEL SAFE
AS $$
  SELECT 12742000.0 * asin(sqrt(
    0.5 - cos(radians(lat2 - lat1)) / 2.0
    + cos(radians(lat1)) * cos(radians(lat2))
      * (1.0 - cos(radians(lon2 - lon1))) / 2.0
  ));
$$;

COMMENT ON FUNCTION public.vp_haversine_meters IS
  'INV-17: Haversine great-circle distance in metres. Used by kinematic guard trigger.';

-- ═══════════════════════════════════════════════════════════════════════════════
-- TRIGGER FUNCTION: vp_kinematic_guard()
--
-- BEFORE INSERT on canonical_facts:
-- 1. Skip if asset_id IS NULL (unregistered device — no timeline to compare).
-- 2. Skip if integrity_flag is already non-OK (don't overwrite upstream flags).
-- 3. Fetch previous OK fact for same (organization_id, asset_id) via index scan.
-- 4. Compute implied speed = haversine(prev, curr) / elapsed_seconds.
-- 5. If speed > 5556 cm/s (200 km/h), set integrity_flag = 'KINEMATIC_ANOMALY'.
-- 6. Always RETURN NEW — never reject the insert (data preservation).
-- ═══════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.vp_kinematic_guard()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  prev_lat       DOUBLE PRECISION;
  prev_lng       DOUBLE PRECISION;
  prev_ts        TIMESTAMPTZ;
  dist_m         DOUBLE PRECISION;
  elapsed_s      DOUBLE PRECISION;
  implied_cms    INTEGER;
  max_speed_cms  CONSTANT INTEGER := 5556;  -- 200 km/h in cm/s
  jump_thresh_m  CONSTANT DOUBLE PRECISION := 5.0;  -- same-timestamp threshold
BEGIN
  -- Step 1: Skip unregistered devices (no asset timeline to compare against)
  IF NEW.asset_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- Step 2: Don't overwrite flags already set by the Edge Function adapter
  IF NEW.integrity_flag <> 'OK' THEN
    RETURN NEW;
  END IF;

  -- Step 2b: Guard against NULL coordinates (schema-change resilient)
  IF NEW.lat IS NULL OR NEW.lng IS NULL THEN
    RETURN NEW;
  END IF;

  -- Step 3: Fetch the most recent OK fact for this asset on its timeline.
  -- Uses idx_canonical_facts_asset_timeline (org_id, asset_id, gps_timestamp ASC)
  -- with a backward scan (DESC + LIMIT 1).
  SELECT cf.lat, cf.lng, cf.gps_timestamp
    INTO prev_lat, prev_lng, prev_ts
    FROM canonical_facts cf
   WHERE cf.organization_id = NEW.organization_id
     AND cf.asset_id        = NEW.asset_id
     AND cf.integrity_flag  = 'OK'
     AND cf.gps_timestamp   < NEW.gps_timestamp
   ORDER BY cf.gps_timestamp DESC
   LIMIT 1;

  -- No previous fact → first event for this asset, nothing to compare
  IF NOT FOUND THEN
    RETURN NEW;
  END IF;

  -- Step 4: Compute distance and elapsed time
  dist_m    := public.vp_haversine_meters(prev_lat, prev_lng, NEW.lat, NEW.lng);
  elapsed_s := EXTRACT(EPOCH FROM (NEW.gps_timestamp - prev_ts));

  -- Step 5a: Same-timestamp or sub-second position jump (cannot compute speed reliably)
  IF elapsed_s < 1.0 THEN
    IF dist_m > jump_thresh_m THEN
      NEW.integrity_flag := 'KINEMATIC_ANOMALY';
    END IF;
    RETURN NEW;
  END IF;

  -- Step 5b: Implied speed check
  -- dist_m / elapsed_s = m/s → × 100 = cm/s
  implied_cms := ROUND(dist_m / elapsed_s * 100.0)::INTEGER;

  IF implied_cms > max_speed_cms THEN
    NEW.integrity_flag := 'KINEMATIC_ANOMALY';
  END IF;

  -- Step 6: Always allow the insert
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.vp_kinematic_guard IS
  'INV-17: BEFORE INSERT trigger that flags GPS teleports as KINEMATIC_ANOMALY. Never rejects data.';

-- ═══════════════════════════════════════════════════════════════════════════════
-- ATTACH TRIGGER
-- ═══════════════════════════════════════════════════════════════════════════════
DROP TRIGGER IF EXISTS trg_kinematic_guard ON canonical_facts;
CREATE TRIGGER trg_kinematic_guard
  BEFORE INSERT ON canonical_facts
  FOR EACH ROW
  EXECUTE FUNCTION public.vp_kinematic_guard();

COMMENT ON TRIGGER trg_kinematic_guard ON canonical_facts IS
  'INV-17: Database-level kinematic guard — flags impossible GPS jumps before storage.';
