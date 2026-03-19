-- ============================================================
-- veraprob — Phase 6: Zone Contractor FK
-- ============================================================
-- REASON:
--   Link operational_zones to the new contractors aggregate.
--   Retains contractor_label as deprecated for compatibility.
-- ============================================================

ALTER TABLE public.operational_zones
  ADD COLUMN IF NOT EXISTS contractor_id UUID REFERENCES public.contractors(id) ON DELETE SET NULL;

-- Index for FK performance
CREATE INDEX idx_operational_zones_contractor ON public.operational_zones (contractor_id);

-- Note: contractor_label is now deprecated. 
-- In Phase 8, we will migrate all existing labels to contractor entities
-- and drop the label column.
