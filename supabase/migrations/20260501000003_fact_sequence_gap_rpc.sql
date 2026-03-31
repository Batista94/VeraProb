-- Phase 9.8.H — Background Sync Resilience: gap-fill RPC
-- Returns canonical facts the OCC client missed while offline.
--
-- Security: SECURITY DEFINER with explicit search_path prevents schema injection.
--           The p_org_id parameter must match the caller's JWT organization_id
--           claim (enforced at the application layer via INV-1).
-- INV-9:    All timestamps are UTC (timestamptz).
-- INV-1:    organization_id is always passed as an explicit parameter.

CREATE OR REPLACE FUNCTION get_missed_facts(
  p_org_id    uuid,
  p_after_utc timestamptz,
  p_limit     int DEFAULT 200
)
RETURNS TABLE (
  id           uuid,
  device_id    text,
  gps_timestamp timestamptz,
  received_at  timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    id,
    device_id,
    gps_timestamp,
    received_at_utc AS received_at
  FROM canonical_facts
  WHERE organization_id = p_org_id
    AND received_at_utc > p_after_utc
  ORDER BY received_at_utc ASC
  LIMIT p_limit;
$$;

REVOKE ALL ON FUNCTION get_missed_facts(uuid, timestamptz, int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_missed_facts(uuid, timestamptz, int) TO authenticated;
