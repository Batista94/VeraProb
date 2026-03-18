-- =============================================================================
-- Phase 6.5.3 — Asset State Machine
-- Migration: asset_status_events (append-only status log)
-- =============================================================================
-- INV-1: Append-only. No UPDATE/DELETE ever.
-- INV-3: occurred_at_utc always UTC.
-- INV-6: organization_id on every record.
-- INV-13: MAINTENANCE and OFF_DUTY states suppress SLA evaluation.
-- =============================================================================

CREATE TABLE IF NOT EXISTS asset_status_events (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id  UUID NOT NULL,
  asset_id         UUID NOT NULL REFERENCES vehicles(id) ON DELETE CASCADE,
  new_status       TEXT NOT NULL CHECK (new_status IN ('ACTIVE', 'MAINTENANCE', 'OFF_DUTY')),
  previous_status  TEXT NOT NULL CHECK (previous_status IN ('ACTIVE', 'MAINTENANCE', 'OFF_DUTY')),
  occurred_at_utc  TIMESTAMPTZ NOT NULL,
  reason           TEXT,
  triggered_by     TEXT NOT NULL, -- user_id or 'SYSTEM'
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Immutability rules at DB level
CREATE RULE asset_status_events_no_update AS
  ON UPDATE TO asset_status_events DO INSTEAD NOTHING;
CREATE RULE asset_status_events_no_delete AS
  ON DELETE TO asset_status_events DO INSTEAD NOTHING;

ALTER TABLE asset_status_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "asset_status_events_org_isolation"
  ON asset_status_events
  FOR ALL
  USING (organization_id = (auth.jwt() ->> 'organization_id')::uuid);

-- Timeline reconstruction: fetch all events for an asset ordered by time
CREATE INDEX idx_asset_status_events_asset_time
  ON asset_status_events(organization_id, asset_id, occurred_at_utc ASC);

-- =============================================================================
-- HELPER FUNCTION: get_current_asset_status(asset_id, organization_id)
-- Returns the most recent status for an asset.
-- Returns 'ACTIVE' if no events exist (default state).
-- =============================================================================
CREATE OR REPLACE FUNCTION get_current_asset_status(
  p_asset_id      UUID,
  p_organization_id UUID
)
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT COALESCE(
    (
      SELECT new_status
      FROM asset_status_events
      WHERE asset_id = p_asset_id
        AND organization_id = p_organization_id
      ORDER BY occurred_at_utc DESC
      LIMIT 1
    ),
    'ACTIVE'
  );
$$;

-- =============================================================================
-- END OF MIGRATION
-- =============================================================================
