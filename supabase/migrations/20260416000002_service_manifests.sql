-- Phase 9.5: ServiceManifest — decouples service definition from asset assignment
CREATE TABLE IF NOT EXISTS service_manifests (
  id              UUID PRIMARY KEY,
  organization_id UUID NOT NULL REFERENCES organizations(id),
  contract_id     UUID NOT NULL REFERENCES contracts(id),
  name            TEXT NOT NULL CHECK (char_length(name) BETWEEN 1 AND 150),
  description     TEXT,
  sla_template_id UUID REFERENCES sla_templates(id),
  vertical        TEXT,
  penalties_payload JSONB NOT NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_service_manifests_org_contract
  ON service_manifests (organization_id, contract_id);

-- RLS: tenant isolation (INV-1)
ALTER TABLE service_manifests ENABLE ROW LEVEL SECURITY;

CREATE POLICY service_manifests_org_isolation
  ON service_manifests
  FOR ALL
  USING (organization_id = (auth.jwt() ->> 'organization_id')::uuid);
