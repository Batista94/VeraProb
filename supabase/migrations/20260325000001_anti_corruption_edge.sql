-- =============================================================================
-- Phase 6.5.1 — Anti-Corruption Edge (Adapters)
-- Migration: provider_api_keys + raw_telemetry_payloads + canonical_facts
-- =============================================================================
-- EXECUTION ORDER: run this file once, top to bottom, in the Supabase SQL Editor.
-- All three tables are created atomically in this single migration.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- TABLE 1: provider_api_keys
-- Maps hashed API keys from hardware providers (Sascar, Omnitracs) to tenants.
-- organization_id is NEVER derived from the inbound payload — only from this table.
-- INV-17: Zero-Trust Tenant Derivation.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS provider_api_keys (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  provider_name   TEXT NOT NULL CHECK (provider_name IN ('SASCAR', 'OMNITRACS', 'MANUAL')),
  api_key_hash    TEXT NOT NULL UNIQUE,   -- SHA-256 of the raw key; plain-text key never stored
  description     TEXT,                  -- e.g. "Frota SP - Sascar contract #123"
  is_active       BOOLEAN NOT NULL DEFAULT true,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Blocked for all authenticated users; Edge Functions use service_role which bypasses RLS.
ALTER TABLE provider_api_keys ENABLE ROW LEVEL SECURITY;
CREATE POLICY "provider_api_keys_blocked_for_jwt_users"
  ON provider_api_keys
  FOR ALL
  USING (false);

-- ---------------------------------------------------------------------------
-- TABLE 2: raw_telemetry_payloads
-- Immutable archive of every raw blob received from hardware providers.
-- Stored BEFORE any parsing — the payload_hash is the forensic seal.
-- INV-1: No UPDATE/DELETE ever.
-- INV-16: received_at_utc is server-side and separate from gps_timestamp.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_telemetry_payloads (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL,
  provider_name   TEXT NOT NULL,
  device_id       TEXT NOT NULL,
  received_at_utc TIMESTAMPTZ NOT NULL DEFAULT NOW(),  -- server-side, immutable anchor
  raw_payload     JSONB NOT NULL,
  payload_hash    TEXT NOT NULL,  -- SHA-256(raw_payload::text) — computed in Edge Function
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE raw_telemetry_payloads ENABLE ROW LEVEL SECURITY;
CREATE POLICY "raw_telemetry_payloads_org_isolation"
  ON raw_telemetry_payloads
  FOR ALL
  USING (organization_id = (auth.jwt() ->> 'organization_id')::uuid);

-- Prevent any UPDATE or DELETE at DB level (immutable ledger pattern).
CREATE RULE raw_telemetry_payloads_no_update AS
  ON UPDATE TO raw_telemetry_payloads DO INSTEAD NOTHING;
CREATE RULE raw_telemetry_payloads_no_delete AS
  ON DELETE TO raw_telemetry_payloads DO INSTEAD NOTHING;

-- Index for audit queries: "give me all raw payloads for org X in time window"
CREATE INDEX idx_raw_telemetry_payloads_org_received
  ON raw_telemetry_payloads(organization_id, received_at_utc DESC);

-- ---------------------------------------------------------------------------
-- TABLE 3: canonical_facts
-- The normalized veraprobEvent — the only representation the Core Domain sees.
-- FK to raw_telemetry_payloads is MANDATORY — no canonical fact without a sealed raw blob.
-- INV-14: Adapter Isolation — raw 3rd-party JSON never touches the Core directly.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS canonical_facts (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id     UUID NOT NULL,
  raw_payload_id      UUID NOT NULL REFERENCES raw_telemetry_payloads(id),  -- forensic anchor
  asset_id            UUID REFERENCES vehicles(id),  -- nullable: device may precede registration
  device_id           TEXT NOT NULL,
  gps_timestamp       TIMESTAMPTZ NOT NULL,           -- device-reported time (variable trust)
  received_at_utc     TIMESTAMPTZ NOT NULL,           -- copy from raw_telemetry_payloads (INV-16)
  lat                 DOUBLE PRECISION NOT NULL CHECK (lat BETWEEN -90 AND 90),
  lng                 DOUBLE PRECISION NOT NULL CHECK (lng BETWEEN -180 AND 180),
  speed_cms           INTEGER CHECK (speed_cms IS NULL OR speed_cms >= 0),  -- cm/s; INV-2
  heading_degrees     SMALLINT CHECK (heading_degrees IS NULL OR heading_degrees BETWEEN 0 AND 359),
  accuracy_meters     REAL,
  source_adapter      TEXT NOT NULL,  -- 'SASCAR_V1' | 'OMNITRACS_V2' | 'MANUAL_UPLOAD'
  integrity_flag      TEXT NOT NULL DEFAULT 'OK'
                        CHECK (integrity_flag IN (
                          'OK',
                          'LATE_ARRIVAL',
                          'FUTURE_TIMESTAMP',
                          'KINEMATIC_ANOMALY',
                          'NULL_ISLAND',
                          'LOW_ACCURACY'
                        )),
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- Idempotency: same device + same gps_timestamp + same adapter = same event.
  -- Second insert is absorbed silently by ON CONFLICT DO NOTHING in the Edge Function.
  UNIQUE (organization_id, device_id, gps_timestamp, source_adapter)
);

ALTER TABLE canonical_facts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "canonical_facts_org_isolation"
  ON canonical_facts
  FOR ALL
  USING (organization_id = (auth.jwt() ->> 'organization_id')::uuid);

-- Primary query path: asset timeline reconstruction ordered by gps_timestamp
CREATE INDEX idx_canonical_facts_asset_timeline
  ON canonical_facts(organization_id, asset_id, gps_timestamp ASC);

-- Secondary: flag-based queries for integrity audits
CREATE INDEX idx_canonical_facts_integrity
  ON canonical_facts(organization_id, integrity_flag)
  WHERE integrity_flag <> 'OK';

-- =============================================================================
-- END OF MIGRATION
-- =============================================================================
