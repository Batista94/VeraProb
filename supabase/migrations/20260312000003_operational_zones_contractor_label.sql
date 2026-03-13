-- Migration: 20260312000003_operational_zones_contractor_label
-- Sprint 5.11 — Anti-Fatigue & UX Excellence
-- Adiciona contractor_label como etiqueta de agrupamento/busca em zonas.
--
-- NÃO é uma FK para uma tabela de contratantes — o agregado Contractor
-- ainda não existe (Phase 6). Este campo é uma tag textual que permite
-- ao Wizard agrupar zonas relacionadas ao cliente do contrato atual
-- (matching por contractor_label == contractorName do contrato).
-- Migração para FK real ocorre na Phase 6.

ALTER TABLE operational_zones
  ADD COLUMN IF NOT EXISTS contractor_label TEXT;

COMMENT ON COLUMN operational_zones.contractor_label IS
  'Etiqueta de agrupamento para associar a zona a um cliente/contratante. '
  'Texto livre — não é FK. Permite ao Wizard de Contrato priorizar zonas '
  'do mesmo cliente. Migrar para FK em Phase 6 quando Contractor aggregate existir.';

-- Index parcial: só indexa linhas onde o label está preenchido
CREATE INDEX IF NOT EXISTS idx_zones_contractor_label
  ON operational_zones(organization_id, contractor_label)
  WHERE contractor_label IS NOT NULL;
