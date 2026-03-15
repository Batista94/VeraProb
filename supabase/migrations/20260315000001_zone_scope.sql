-- Sprint 5.13 Bloco 2.1 — Zone Taxonomy
-- Adiciona coluna gerada zone_scope derivada de contractor_label.
-- NULL contractor_label → 'global' (zona do operador, visível a todos)
-- non-NULL contractor_label → 'exclusive' (zona ligada a um contratante)
-- Phase 6: quando contractor_label migrar para FK contractor_id,
--           esta coluna gerada será substituída por coluna real.

ALTER TABLE public.operational_zones
  ADD COLUMN IF NOT EXISTS zone_scope TEXT
    GENERATED ALWAYS AS (
      CASE WHEN contractor_label IS NULL THEN 'global' ELSE 'exclusive' END
    ) STORED;

CREATE INDEX IF NOT EXISTS idx_zones_scope
  ON public.operational_zones (organization_id, zone_scope);

ALTER TABLE public.operational_zones
  DROP CONSTRAINT IF EXISTS chk_zone_scope;

ALTER TABLE public.operational_zones
  ADD CONSTRAINT chk_zone_scope
    CHECK (zone_scope IN ('global', 'exclusive'));
