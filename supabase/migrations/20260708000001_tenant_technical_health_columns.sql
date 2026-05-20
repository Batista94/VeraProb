-- ── Migration 20260708000001 ─────────────────────────────────────────────────
-- Adiciona três colunas de saúde técnica de schema à tabela organizations.
--
-- Colunas:
--   schema_integrity_status  — resultado da última verificação de integridade
--   schema_version           — versão detectada do schema (date-based string)
--   last_schema_check_at     — timestamp UTC da última execução do RPC
--
-- Invariants:
--   INV-3  — organizations não é ledger; UPDATE é permitido (quota updates já existem).
--   INV-6  — last_schema_check_at usa TIMESTAMPTZ (INV-6 mandatory).
--   INV-DB — apenas ADD COLUMN IF NOT EXISTS; sem ALTER COLUMN, DROP ou TRUNCATE.
--
-- Idempotência: ADD COLUMN IF NOT EXISTS é seguro para re-execução.
-- DEVE rodar ANTES de 20260708000002 (VIEW referencia essas colunas).
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. Adicionar colunas ──────────────────────────────────────────────────────

ALTER TABLE public.organizations
  ADD COLUMN IF NOT EXISTS schema_integrity_status TEXT
    NOT NULL DEFAULT 'unknown',
  ADD COLUMN IF NOT EXISTS schema_version TEXT
    NOT NULL DEFAULT 'unknown',
  ADD COLUMN IF NOT EXISTS last_schema_check_at TIMESTAMPTZ;

-- ── 2. CHECK NOT VALID (sem lock de tabela) ───────────────────────────────────

ALTER TABLE public.organizations
  ADD CONSTRAINT chk_schema_integrity_status
    CHECK (schema_integrity_status IN (
      'compliant', 'minor_drift', 'critical_drift', 'unknown'
    )) NOT VALID;

-- ── 3. VALIDATE (aplica constraint sem lock de escrita) ───────────────────────

ALTER TABLE public.organizations
  VALIDATE CONSTRAINT chk_schema_integrity_status;

-- ── 4. Comentários ───────────────────────────────────────────────────────────

COMMENT ON COLUMN public.organizations.schema_integrity_status IS
  'Status da última verificação de integridade de schema pelo RPC check_schema_integrity. Valores: compliant | minor_drift | critical_drift | unknown.';

COMMENT ON COLUMN public.organizations.schema_version IS
  'Versão detectada do schema (string date-based YYYY-MM-DD). Atualizada pelo RPC check_schema_integrity.';

COMMENT ON COLUMN public.organizations.last_schema_check_at IS
  'Timestamp UTC da última execução bem-sucedida do RPC check_schema_integrity. INV-6: TIMESTAMPTZ.';
