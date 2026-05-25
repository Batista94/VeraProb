-- Migration: Universal CSV Mapping Engine templates
-- INV-1:  organization_id tenant isolation
-- INV-2:  RLS via JWT app_metadata.org_id
-- INV-6:  TIMESTAMPTZ mandatory
-- INV-14: Agnostic target fields (Asset properties, not "veículo/placa")
-- INV-DB: Non-destructive CREATE (no ALTER/DROP on existing tables)

-- ── Table ────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.csv_mapping_templates (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id   UUID        NOT NULL,
  name              TEXT        NOT NULL,
  target_entity     TEXT        NOT NULL
    CONSTRAINT chk_cmt_target_entity
      CHECK (target_entity IN ('asset', 'contract', 'zone', 'operator')),
  column_mappings   JSONB       NOT NULL DEFAULT '[]'::JSONB,
  is_default        BOOLEAN     NOT NULL DEFAULT FALSE,
  version           INT         NOT NULL DEFAULT 1,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by        UUID        NULL,

  -- Unique template name per org+entity (prevent confusion)
  CONSTRAINT uq_cmt_org_entity_name
    UNIQUE (organization_id, target_entity, name)
);

COMMENT ON TABLE public.csv_mapping_templates IS
  'Persists user-defined CSV column-to-entity-field mappings per tenant (INV-14: agnostic).';

COMMENT ON COLUMN public.csv_mapping_templates.column_mappings IS
  'JSONB array: [{"csv_header": "PLACA", "target_field": "identifier", "transform": "uppercase"}, ...]';

COMMENT ON COLUMN public.csv_mapping_templates.target_entity IS
  'Agnostic entity type (INV-14): asset | contract | zone | operator';

-- ── Indexes ──────────────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_cmt_org_entity
  ON public.csv_mapping_templates (organization_id, target_entity);

CREATE INDEX IF NOT EXISTS idx_cmt_org_default
  ON public.csv_mapping_templates (organization_id, target_entity)
  WHERE is_default = TRUE;

-- ── Optimistic Lock Trigger ──────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.csv_mapping_template_version_bump()
RETURNS TRIGGER AS $$
BEGIN
  NEW.version := OLD.version + 1;
  NEW.updated_at := now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_cmt_version_bump ON public.csv_mapping_templates;
CREATE TRIGGER trg_cmt_version_bump
  BEFORE UPDATE ON public.csv_mapping_templates
  FOR EACH ROW EXECUTE FUNCTION public.csv_mapping_template_version_bump();

-- ── RLS ──────────────────────────────────────────────────────────────────
-- INV-2: auth.jwt() -> 'app_metadata' ->> 'org_id' (NEVER auth.uid())
-- INV-22: Physical tenant isolation

ALTER TABLE public.csv_mapping_templates ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "CSV mapping template tenant isolation" ON public.csv_mapping_templates;
CREATE POLICY "CSV mapping template tenant isolation"
  ON public.csv_mapping_templates FOR ALL TO authenticated
  USING     (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::UUID)
  WITH CHECK (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::UUID);
