-- ============================================================
-- veraprob — Device Heartbeat Status View: security_invoker Hardening
-- ============================================================
-- REASON:
--   vw_device_heartbeat_status was created without security_invoker,
--   meaning the view defaulted to SECURITY DEFINER behavior.
--   This would bypass RLS checks on the underlying tables.
--   
--   Fix: recreate with WITH (security_invoker = true) so
--   PostgreSQL evaluates RLS policies of the calling user
--   on canonical_facts (INV-2, INV-22).
--
-- SECURITY INVARIANTS:
--   INV-1  — organization_id filter on ALL flows
--   INV-2  — RLS via auth.jwt() claims
--   INV-11 — Views in public schema must use WITH (security_invoker = true)
--   INV-22 — Tenant-A NEVER sees Tenant-B data.
-- ============================================================

SET client_min_messages TO 'WARNING';

-- Drop the existing view. Use CASCADE because get_device_heartbeat_status(UUID)
-- depends on this view and will be dropped.
DROP VIEW IF EXISTS public.vw_device_heartbeat_status CASCADE;

-- Recreate view with security_invoker = true
CREATE VIEW public.vw_device_heartbeat_status
  WITH (security_invoker = true)
AS
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

COMMENT ON VIEW public.vw_device_heartbeat_status IS
  'Device Heartbeat Status View: security_invoker=true (INV-11). Calls evaluate RLS on underlying canonical_facts.';

-- Restrict direct access: only postgres and service_role may query the view directly.
REVOKE ALL ON public.vw_device_heartbeat_status FROM PUBLIC;
REVOKE ALL ON public.vw_device_heartbeat_status FROM authenticated;
REVOKE ALL ON public.vw_device_heartbeat_status FROM anon;
GRANT SELECT ON public.vw_device_heartbeat_status TO service_role;

-- Recreate the dependent RPC function get_device_heartbeat_status(UUID)
-- scoped to the organization of the caller.
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
