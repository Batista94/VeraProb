-- Phase 4: Operational Alerts
-- Derived alert events from contractual evaluation pipeline

CREATE TABLE operational_alerts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id),
  entity_id TEXT NOT NULL,
  contract_id TEXT NOT NULL,
  alert_type TEXT NOT NULL,
  severity TEXT NOT NULL,
  triggered_at_utc TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- NOTE: FK to sla_audit_ledger_v2 omitted intentionally.
  -- sla_audit_ledger_v2 is HASH-partitioned with composite PK (organization_id, id).
  -- PostgreSQL does not support FKs referencing a partial composite PK on partitioned tables.
  -- Referential integrity is enforced at the application layer (handlers always write
  -- the ledger entry before persisting any derived projection).
  triggering_event_id UUID,
  trace_id UUID REFERENCES contractual_evaluation_traces(id),
  context JSONB NOT NULL DEFAULT '{}',
  status TEXT NOT NULL DEFAULT 'ACTIVE',
  acknowledged_at_utc TIMESTAMPTZ,
  acknowledged_by_user_id UUID,
  resolved_at_utc TIMESTAMPTZ,

  CONSTRAINT valid_alert_type CHECK (alert_type IN ('NO_SHOW', 'EVIDENCE_GAP', 'PENALTY_APPLIED')),
  CONSTRAINT valid_severity CHECK (severity IN ('CRITICAL', 'HIGH', 'WARNING')),
  CONSTRAINT valid_status CHECK (status IN ('ACTIVE', 'ACKNOWLEDGED', 'RESOLVED')),
  CONSTRAINT unique_alert_per_event UNIQUE (triggering_event_id, alert_type)
);

-- Tenant isolation via Row Level Security
ALTER TABLE operational_alerts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "org_isolation_select" ON operational_alerts
  FOR SELECT USING (organization_id = (auth.jwt() ->> 'organization_id')::uuid);

CREATE POLICY "org_isolation_insert" ON operational_alerts
  FOR INSERT WITH CHECK (organization_id = (auth.jwt() ->> 'organization_id')::uuid);

CREATE POLICY "org_isolation_update" ON operational_alerts
  FOR UPDATE USING (organization_id = (auth.jwt() ->> 'organization_id')::uuid);

-- Triage queries: active alerts by organization, ordered by severity then time
-- Supports OCC sort: CRITICAL first, then HIGH, then WARNING, most recent first
CREATE INDEX idx_alerts_active ON operational_alerts (organization_id, status, severity, triggered_at_utc DESC);

-- Entity lookup for investigation correlation
CREATE INDEX idx_alerts_entity ON operational_alerts (entity_id, triggered_at_utc DESC);

-- Idempotency enforcement index (supports UNIQUE constraint performance)
CREATE INDEX idx_alerts_idempotency ON operational_alerts (triggering_event_id, alert_type);

-- Revoke direct mutation from service role (lifecycle managed through AlertService)
REVOKE DELETE ON operational_alerts FROM authenticated;
