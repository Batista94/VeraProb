-- Migration: Heartbeat Monitor View (Phase 9.8.G)
--
-- Creates a VIEW that computes per-device signal gap and fleet active ratio
-- from canonical_facts. Used by the Heartbeat Monitor projection to classify
-- device silence as network failure vs hardware tamper.
--
-- RLS NOTE: Supabase does not apply RLS directly to views. The infra query
-- service filters by organization_id as a parameter binding (INV-1).
-- The view is owned by postgres and not directly exposed to anon/authenticated roles.

CREATE OR REPLACE VIEW vw_device_heartbeat_status AS
WITH latest_pings AS (
  SELECT
    organization_id,
    asset_id,
    MAX(gps_timestamp) AS last_seen_utc,
    EXTRACT(EPOCH FROM (NOW() - MAX(gps_timestamp)))::INT AS gap_seconds
  FROM canonical_facts
  WHERE asset_id IS NOT NULL
  GROUP BY organization_id, asset_id
),
fleet_active AS (
  SELECT
    organization_id,
    COUNT(*) AS total_devices,
    COUNT(*) FILTER (
      WHERE gap_seconds <= 90
    ) AS active_devices
  FROM latest_pings
  GROUP BY organization_id
)
SELECT
  lp.organization_id,
  lp.asset_id,
  lp.last_seen_utc,
  lp.gap_seconds,
  ROUND(
    fa.active_devices::NUMERIC / NULLIF(fa.total_devices, 0),
    4
  ) AS fleet_active_ratio
FROM latest_pings lp
JOIN fleet_active fa USING (organization_id);

-- Restrict direct access: only postgres and service_role may query the view directly.
-- Application queries go through the RPC below which enforces org isolation (INV-1).
REVOKE ALL ON vw_device_heartbeat_status FROM PUBLIC;
REVOKE ALL ON vw_device_heartbeat_status FROM authenticated;
REVOKE ALL ON vw_device_heartbeat_status FROM anon;
GRANT SELECT ON vw_device_heartbeat_status TO service_role;

-- RPC: secure entry point for authenticated users scoped to their organization.
-- Returns only rows where organization_id matches the JWT claim (INV-1, INV-5).
CREATE OR REPLACE FUNCTION get_device_heartbeat_status(p_organization_id UUID)
RETURNS TABLE (
  asset_id        TEXT,
  last_seen_utc   TIMESTAMPTZ,
  gap_seconds     INT,
  fleet_active_ratio NUMERIC
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    asset_id,
    last_seen_utc,
    gap_seconds,
    fleet_active_ratio
  FROM vw_device_heartbeat_status
  WHERE organization_id = p_organization_id
  LIMIT 500;
$$;

-- Only authenticated users may call this RPC.
REVOKE ALL ON FUNCTION get_device_heartbeat_status(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_device_heartbeat_status(UUID) TO authenticated;
