-- ── Migration 20260520180000 ─────────────────────────────────────────────────
-- CT10: Adiciona 4 colunas de configuração avançada à tabela organizations.
--
-- Colunas:
--   clock_drift_tolerance_s  — Motor Forense: drift máximo aceito (segundos)
--   data_retention_days      — Compliance: retenção de evidências online (dias)
--   connection_pool_limit    — Infra: conexões máximas Postgres por tenant
--   storage_quota_gb         — Infra: limite de armazenamento de evidências (GB)
--
-- INV-DB (Zero-Downtime):
--   ADD COLUMN com DEFAULT é instantâneo no Postgres 11+.
--   Constraints seguem padrão 3-passos: CHECK NOT VALID → VALIDATE.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. Adicionar colunas ──────────────────────────────────────────────────────

ALTER TABLE public.organizations
  ADD COLUMN IF NOT EXISTS clock_drift_tolerance_s   INT NOT NULL DEFAULT 300,
  ADD COLUMN IF NOT EXISTS data_retention_days        INT NOT NULL DEFAULT 1825,
  ADD COLUMN IF NOT EXISTS connection_pool_limit      INT NOT NULL DEFAULT 60,
  ADD COLUMN IF NOT EXISTS storage_quota_gb           INT NOT NULL DEFAULT 100;

-- ── 2. CHECK NOT VALID (sem lock de tabela) ───────────────────────────────────

ALTER TABLE public.organizations
  ADD CONSTRAINT chk_clock_drift_tolerance_s
    CHECK (clock_drift_tolerance_s >= 0) NOT VALID;

ALTER TABLE public.organizations
  ADD CONSTRAINT chk_data_retention_days
    CHECK (data_retention_days >= 1) NOT VALID;

ALTER TABLE public.organizations
  ADD CONSTRAINT chk_connection_pool_limit
    CHECK (connection_pool_limit >= 1 AND connection_pool_limit <= 500) NOT VALID;

ALTER TABLE public.organizations
  ADD CONSTRAINT chk_storage_quota_gb
    CHECK (storage_quota_gb >= 1) NOT VALID;

-- ── 3. VALIDATE (aplica constraint sem lock de escrita) ───────────────────────

ALTER TABLE public.organizations
  VALIDATE CONSTRAINT chk_clock_drift_tolerance_s;

ALTER TABLE public.organizations
  VALIDATE CONSTRAINT chk_data_retention_days;

ALTER TABLE public.organizations
  VALIDATE CONSTRAINT chk_connection_pool_limit;

ALTER TABLE public.organizations
  VALIDATE CONSTRAINT chk_storage_quota_gb;

-- ── 4. Comentários ───────────────────────────────────────────────────────────

COMMENT ON COLUMN public.organizations.clock_drift_tolerance_s IS
  'Motor Forense: máximo clock drift tolerado em segundos (CT10). Padrão: 300s.';

COMMENT ON COLUMN public.organizations.data_retention_days IS
  'Compliance: dias de retenção de evidências online (CT10). Padrão: 1825 (5 anos).';

COMMENT ON COLUMN public.organizations.connection_pool_limit IS
  'Infra: limite rígido de conexões Postgres por tenant (CT10, INV-16). Padrão: 60.';

COMMENT ON COLUMN public.organizations.storage_quota_gb IS
  'Infra: limite de armazenamento de evidências em GB (CT10). Padrão: 100 GB.';
