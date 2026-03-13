-- Migration: 20260312000001_sla_templates
-- Sprint 5.11 — Anti-Fatigue & UX Excellence
-- Cria tabela de templates de SLA reutilizáveis (org-scoped, JSONB payload).
-- SLAPenalties permanece um Value Object puro no domínio — o template é
-- apenas um preset nomeado de application layer.

CREATE TABLE IF NOT EXISTS sla_templates (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id   UUID        NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  name              TEXT        NOT NULL CHECK (char_length(name) BETWEEN 1 AND 100),
  description       TEXT,
  -- Serialização completa de SLAPenalties (todos os campos, incluindo os 3 adicionados na Sprint 5.10 Fase 2)
  penalties_payload JSONB       NOT NULL,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- RLS: isolamento por tenant (idêntico ao padrão de operational_zones)
ALTER TABLE sla_templates ENABLE ROW LEVEL SECURITY;

CREATE POLICY "sla_templates_org_isolation"
  ON sla_templates
  USING  (organization_id = (auth.jwt() ->> 'organization_id')::uuid)
  WITH CHECK (organization_id = (auth.jwt() ->> 'organization_id')::uuid);

-- Index para leitura por org (o único padrão de acesso relevante)
CREATE INDEX IF NOT EXISTS idx_sla_templates_org
  ON sla_templates(organization_id);
