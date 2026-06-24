-- =============================================================================
-- Migration: dispute_reason_codes — Structured Taxonomy (global closed catalogue)
-- B6: `code` is industry-agnostic (survives a vertical change). Transport wording
--     lives ONLY in label_pt / label_en. No custom codes in v1 (Q2).
-- Invariants: INV-1, INV-2, INV-3, INV-6, INV-DB.
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.dispute_reason_codes (
  code              TEXT        PRIMARY KEY,
  category          TEXT        NOT NULL
    CONSTRAINT chk_reason_category CHECK (
      category IN ('OPERATIONAL','TECHNICAL','CONTRACTUAL','ENVIRONMENTAL','REGULATORY','OTHER')
    ),
  label_pt          TEXT        NOT NULL,
  label_en          TEXT        NOT NULL,
  description       TEXT,
  applies_to        TEXT        NOT NULL DEFAULT 'ALL'
    CONSTRAINT chk_reason_applies CHECK (applies_to IN ('REJECTION','RESOLUTION','ALL')),
  is_active         BOOLEAN     NOT NULL DEFAULT TRUE,
  is_custom         BOOLEAN     NOT NULL DEFAULT FALSE,
  organization_id   UUID        REFERENCES public.organizations(id),  -- NULL = global
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT uq_reason_code_org UNIQUE (code, organization_id)
);

-- ── Seed (B6: agnostic codes; vertical term only in labels) ──────────────────
INSERT INTO public.dispute_reason_codes
  (code, category, label_pt, label_en, applies_to, is_custom) VALUES
  ('FORCE_MAJEURE',         'ENVIRONMENTAL', 'Força Maior',                'Force Majeure',              'ALL', FALSE),
  ('SENSOR_FAULT',          'TECHNICAL',     'Falha de Sensor',            'Sensor Fault',               'ALL', FALSE),
  ('GPS_SIGNAL_LOSS',       'TECHNICAL',     'Perda de Sinal GPS',         'GPS Signal Loss',            'ALL', FALSE),
  ('CONTRACT_EXCEPTION',    'CONTRACTUAL',   'Exceção Contratual',         'Contract Exception',         'ALL', FALSE),
  ('ROUTE_DEVIATION',       'OPERATIONAL',   'Desvio de Rota Autorizado',  'Authorized Route Deviation', 'ALL', FALSE),
  ('WEATHER_EVENT',         'ENVIRONMENTAL', 'Evento Climático',           'Weather Event',              'ALL', FALSE),
  ('TRAFFIC_INCIDENT',      'OPERATIONAL',   'Acidente/Interdição de Via', 'Traffic Incident',           'ALL', FALSE),
  ('ASSET_BREAKDOWN',       'TECHNICAL',     'Pane do Ativo (Veículo)',    'Asset Breakdown (Vehicle)',  'ALL', FALSE),
  ('OPERATOR_EMERGENCY',    'OPERATIONAL',   'Emergência do Operador',     'Operator Emergency',         'ALL', FALSE),
  ('REGULATORY_INTERVENTION','REGULATORY',   'Intervenção Regulatória (Blitz)','Regulatory Intervention','ALL', FALSE),
  ('COMMUNICATION_FAILURE', 'TECHNICAL',     'Falha de Comunicação',       'Communication Failure',      'ALL', FALSE),
  ('SCHEDULING_ERROR',      'OPERATIONAL',   'Erro de Programação',        'Scheduling Error',           'ALL', FALSE),
  ('THIRD_PARTY_INCIDENT',  'OPERATIONAL',   'Incidente com Terceiro',     'Third-Party Incident',       'ALL', FALSE),
  ('INFRASTRUCTURE_FAULT',  'OPERATIONAL',   'Falha de Infraestrutura',    'Infrastructure Fault',       'ALL', FALSE),
  ('OTHER',                 'OTHER',         'Outro (ver comentário)',     'Other (see comment)',        'ALL', FALSE),
  ('LEGACY_UNCLASSIFIED',   'OTHER',         'Legado Não Classificado',    'Legacy Unclassified',        'ALL', FALSE)
ON CONFLICT (code, organization_id) DO NOTHING;

ALTER TABLE public.dispute_reason_codes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS drc_select_global ON public.dispute_reason_codes;
CREATE POLICY drc_select_global
  ON public.dispute_reason_codes FOR SELECT
  USING (
    organization_id IS NULL
    OR organization_id = ((auth.jwt() -> 'app_metadata' ->> 'org_id')::UUID)
  );

-- Q2: INSERT/UPDATE BLOCKED in v1 (no policy = no client-side creation).
-- FUTURE custom-codes phase MUST mandate organization_id IS NOT NULL in any
-- INSERT policy it adds, or org-scoped codes would bleed globally (M-qa).

GRANT SELECT ON TABLE public.dispute_reason_codes TO authenticated;  -- not anon (C6)
GRANT ALL ON TABLE public.dispute_reason_codes TO service_role;
