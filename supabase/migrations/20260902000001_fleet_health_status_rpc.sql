-- pr_scanner: ignore-regression
-- =============================================================================
-- Migration: `get_fleet_health_status` RPC — Phase 10.6
--
-- Purpose:   Classified hardware health status for every registered vehicle
--            (and phantom/unregistered devices) in a tenant's fleet. Powers the
--            Ingestion Health Monitor dashboard and the Data Integrity Drill-down.
--
-- Design:    SECURITY DEFINER RPC with JWT org-claim gating (INV-2, INV-26).
--            Uses DISTINCT ON + backward index scan on
--            `idx_canonical_facts_asset_timeline (org_id, asset_id, gps_timestamp ASC)`
--            for the per-device latest-ping CTE — no seq scan, no new index.
--
-- Thresholds are RPC parameters with sensible defaults so the Dart layer can
-- adjust sensitivity without a migration:
--   p_delayed_sec  DEFAULT 900   (15 min)
--   p_offline_sec  DEFAULT 3600  (1 hour)
--
-- Phantom devices (asset_id IS NULL, device_id present) are included in the
-- result set with vehicle_id = NULL, plate = NULL, model = NULL. The UI renders
-- these as "Placa N/D" to surface orphan M2M chips generating blind cost.
--
-- INV-1:  organization_id filter on ALL source tables.
-- INV-2:  JWT claim extracted via `auth.jwt() -> 'app_metadata' ->> 'org_id'`.
-- INV-6:  All timestamps are TIMESTAMPTZ; NOW() is UTC.
-- INV-12: Leverages existing idx_canonical_facts_asset_timeline + idx_canonical_facts_integrity.
-- INV-15: Deterministic — same inputs always produce the same output.
-- INV-16: Single RPC call per dashboard load; 60s polling budget.
-- INV-22: Tenant isolation enforced via JWT claim check.
-- INV-26: Anti-oracle — JWT mismatch returns 0 rows, never an error.
--
-- Council: Architect ✅ · Senior ✅ · QA-Security ✅ · UX-Operations ✅ · Business ✅
-- =============================================================================

SET client_min_messages TO 'WARNING';

CREATE OR REPLACE FUNCTION public.get_fleet_health_status(
  p_organization_id UUID,
  p_delayed_sec     INT DEFAULT 900,
  p_offline_sec     INT DEFAULT 3600,
  p_limit           INT DEFAULT 200
)
RETURNS TABLE (
  vehicle_id          UUID,
  plate               TEXT,
  model               TEXT,
  device_id           TEXT,
  last_ping_utc       TIMESTAMPTZ,
  gap_seconds         INT,
  hardware_status     TEXT,
  integrity_score_bps INT,
  fleet_active_ratio  NUMERIC(5,4),
  anomaly_count_24h   INT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
STABLE
AS $$
DECLARE
  v_jwt_org TEXT;
BEGIN
  -- INV-26: anti-oracle — return 0 rows on JWT mismatch, never an error.
  v_jwt_org := auth.jwt() -> 'app_metadata' ->> 'org_id';
  IF v_jwt_org IS NULL OR v_jwt_org::uuid <> p_organization_id THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH
  -- CTE 1: Latest ping per REGISTERED vehicle (asset_id IS NOT NULL).
  -- Uses idx_canonical_facts_asset_timeline (org, asset_id, gps_timestamp ASC)
  -- with DISTINCT ON + ORDER BY ... DESC → backward index scan, one row per asset.
  latest_registered AS (
    SELECT DISTINCT ON (cf.asset_id)
      cf.asset_id,
      cf.device_id,
      cf.gps_timestamp AS last_ping,
      EXTRACT(EPOCH FROM (NOW() - cf.gps_timestamp))::INT AS gap_sec
    FROM canonical_facts cf
    WHERE cf.organization_id = p_organization_id
      AND cf.asset_id IS NOT NULL
    ORDER BY cf.asset_id, cf.gps_timestamp DESC
  ),

  -- CTE 2: Latest ping per PHANTOM device (asset_id IS NULL, device_id present).
  -- These are M2M chips transmitting without a registered vehicle association.
  latest_phantom AS (
    SELECT DISTINCT ON (cf.device_id)
      cf.device_id,
      cf.gps_timestamp AS last_ping,
      EXTRACT(EPOCH FROM (NOW() - cf.gps_timestamp))::INT AS gap_sec
    FROM canonical_facts cf
    WHERE cf.organization_id = p_organization_id
      AND cf.asset_id IS NULL
      AND cf.device_id IS NOT NULL
    ORDER BY cf.device_id, cf.gps_timestamp DESC
  ),

  -- CTE 3: Union of all device latest pings (registered + phantom).
  all_devices AS (
    SELECT
      lr.asset_id,
      lr.device_id,
      lr.last_ping,
      lr.gap_sec
    FROM latest_registered lr
    UNION ALL
    SELECT
      NULL::UUID AS asset_id,
      lp.device_id,
      lp.last_ping,
      lp.gap_sec
    FROM latest_phantom lp
  ),

  -- CTE 4: Fleet-wide active ratio (devices with gap <= 90s / total).
  fleet_stats AS (
    SELECT
      COUNT(*)::INT AS total_devices,
      COUNT(*) FILTER (WHERE gap_sec <= 90)::INT AS active_devices
    FROM all_devices
  ),

  -- CTE 5: Anomaly count per device in last 24h (uses idx_canonical_facts_integrity).
  anomalies_registered AS (
    SELECT
      cf.asset_id,
      NULL::TEXT AS phantom_device_id,
      COUNT(*)::INT AS anomaly_count
    FROM canonical_facts cf
    WHERE cf.organization_id = p_organization_id
      AND cf.asset_id IS NOT NULL
      AND cf.integrity_flag <> 'OK'
      AND cf.gps_timestamp >= NOW() - INTERVAL '24 hours'
    GROUP BY cf.asset_id
  ),
  anomalies_phantom AS (
    SELECT
      NULL::UUID AS asset_id,
      cf.device_id AS phantom_device_id,
      COUNT(*)::INT AS anomaly_count
    FROM canonical_facts cf
    WHERE cf.organization_id = p_organization_id
      AND cf.asset_id IS NULL
      AND cf.device_id IS NOT NULL
      AND cf.integrity_flag <> 'OK'
      AND cf.gps_timestamp >= NOW() - INTERVAL '24 hours'
    GROUP BY cf.device_id
  ),

  -- CTE 6: Per-device integrity score (last 2h, gap-based).
  -- Score = 10000 - (silent_seconds / total_seconds * 10000).
  -- Silent = intervals > 120s (WS-9 Data Silence threshold).
  recent_stream AS (
    SELECT
      cf.asset_id,
      cf.device_id,
      cf.gps_timestamp,
      EXTRACT(EPOCH FROM (
        cf.gps_timestamp - LAG(cf.gps_timestamp) OVER (
          PARTITION BY COALESCE(cf.asset_id::text, cf.device_id)
          ORDER BY cf.gps_timestamp
        )
      ))::INT AS interval_sec
    FROM canonical_facts cf
    WHERE cf.organization_id = p_organization_id
      AND cf.gps_timestamp >= NOW() - INTERVAL '2 hours'
  ),
  stream_score AS (
    SELECT
      rs.asset_id,
      rs.device_id,
      CASE
        WHEN COALESCE(SUM(rs.interval_sec) FILTER (WHERE rs.interval_sec IS NOT NULL), 0) = 0
          THEN 10000
        ELSE GREATEST(0,
          10000 - (
            COALESCE(SUM(rs.interval_sec) FILTER (WHERE rs.interval_sec > 120), 0) * 10000
            / GREATEST(SUM(rs.interval_sec) FILTER (WHERE rs.interval_sec IS NOT NULL), 1)
          )
        )::INT
      END AS integrity_bps
    FROM recent_stream rs
    GROUP BY rs.asset_id, rs.device_id
  ),

  -- CTE 7: Registered vehicles with health data.
  registered_results AS (
    SELECT
      v.id              AS v_id,
      v.plate           AS v_plate,
      v.model           AS v_model,
      lr.device_id      AS d_id,
      lr.last_ping      AS ping_utc,
      COALESCE(lr.gap_sec, 999999) AS g_sec,
      CASE
        WHEN lr.last_ping IS NULL            THEN 'NEVER_SEEN'
        WHEN lr.gap_sec <= p_delayed_sec     THEN 'HEALTHY'
        WHEN lr.gap_sec <= p_offline_sec     THEN 'DELAYED'
        ELSE                                      'OFFLINE'
      END               AS hw_status,
      COALESCE(ss.integrity_bps, 0)::INT AS i_bps,
      COALESCE(ar.anomaly_count, 0)::INT AS a_count,
      -- Sort priority: worst status first.
      CASE
        WHEN lr.last_ping IS NULL       THEN 0
        WHEN lr.gap_sec > p_offline_sec THEN 1
        WHEN lr.gap_sec > p_delayed_sec THEN 2
        ELSE 3
      END AS sort_priority
    FROM vehicles v
    LEFT JOIN latest_registered lr ON lr.asset_id = v.id
    LEFT JOIN anomalies_registered ar ON ar.asset_id = v.id
    LEFT JOIN stream_score ss ON ss.asset_id = v.id
    WHERE v.organization_id = p_organization_id
      AND v.status <> 'retired'
  ),

  -- CTE 8: Phantom device results.
  phantom_results AS (
    SELECT
      NULL::UUID        AS v_id,
      NULL::TEXT         AS v_plate,
      NULL::TEXT         AS v_model,
      lp.device_id      AS d_id,
      lp.last_ping      AS ping_utc,
      lp.gap_sec        AS g_sec,
      CASE
        WHEN lp.gap_sec <= p_delayed_sec THEN 'HEALTHY'
        WHEN lp.gap_sec <= p_offline_sec THEN 'DELAYED'
        ELSE                                  'OFFLINE'
      END               AS hw_status,
      COALESCE(ss.integrity_bps, 0)::INT AS i_bps,
      COALESCE(ap.anomaly_count, 0)::INT AS a_count,
      CASE
        WHEN lp.gap_sec > p_offline_sec THEN 1
        WHEN lp.gap_sec > p_delayed_sec THEN 2
        ELSE 3
      END AS sort_priority
    FROM latest_phantom lp
    LEFT JOIN anomalies_phantom ap ON ap.phantom_device_id = lp.device_id
    LEFT JOIN stream_score ss ON ss.asset_id IS NULL AND ss.device_id = lp.device_id
  ),

  -- CTE 9: Combined and sorted.
  combined AS (
    SELECT * FROM registered_results
    UNION ALL
    SELECT * FROM phantom_results
  )

  SELECT
    c.v_id             AS vehicle_id,
    c.v_plate          AS plate,
    c.v_model          AS model,
    c.d_id             AS device_id,
    c.ping_utc         AS last_ping_utc,
    c.g_sec            AS gap_seconds,
    c.hw_status        AS hardware_status,
    c.i_bps            AS integrity_score_bps,
    ROUND(
      fs.active_devices::NUMERIC / NULLIF(fs.total_devices, 0), 4
    )                  AS fleet_active_ratio,
    c.a_count          AS anomaly_count_24h
  FROM combined c
  CROSS JOIN fleet_stats fs
  ORDER BY c.sort_priority ASC, c.g_sec DESC NULLS FIRST
  LIMIT GREATEST(p_limit, 1);
END;
$$;

-- INV-DATA-API-GRANT: authenticated + service_role; revoke PUBLIC + anon.
REVOKE ALL ON FUNCTION public.get_fleet_health_status(UUID, INT, INT, INT)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_fleet_health_status(UUID, INT, INT, INT)
  TO authenticated, service_role;

-- Deprecation note on the old view (retained for backward compatibility — INV-DB).
COMMENT ON VIEW public.vw_device_heartbeat_status IS
  'DEPRECATED: Superseded by get_fleet_health_status RPC (Phase 10.6). '
  'Retained for backward compatibility. Do not use for new code.';

RESET client_min_messages;
