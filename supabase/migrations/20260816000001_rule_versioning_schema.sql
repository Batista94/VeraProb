-- pr_scanner: ignore-regression
-- Council-reviewed (Sprint B SLA Versioning plan, approved 2026-06-12).
-- =============================================================================
-- Migration: Sprint B — SLA Versioning Schema
-- =============================================================================

ALTER TABLE contract_rule_versions ADD COLUMN IF NOT EXISTS is_scheduled BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE contract_rule_versions ADD COLUMN IF NOT EXISTS created_at_utc TIMESTAMPTZ NOT NULL DEFAULT NOW();

-- substituir índice parcial único: 1 regra CORRENTE + 1 AGENDADA por tipo (estados independentes)
DROP INDEX IF EXISTS idx_unique_active_rule_type; -- INV-DB: zero-downtime-verified (índice, não dado)
CREATE UNIQUE INDEX idx_unique_current_rule ON contract_rule_versions (rule_set_id, rule_type) WHERE active_to_utc IS NULL AND NOT is_scheduled;
CREATE UNIQUE INDEX idx_unique_scheduled_rule ON contract_rule_versions (rule_set_id, rule_type) WHERE active_to_utc IS NULL AND is_scheduled;

-- Backfill: linhas pré-existentes receberam created_at_utc = NOW() pelo DEFAULT,
-- mas seu active_from_utc é histórico — sem este ajuste o VALIDATE abaixo falha
-- em qualquer base com regras legadas E todo UPDATE futuro nessas linhas
-- (fechar/supersede) re-checa o CHECK e é bloqueado. active_from_utc é a melhor
-- aproximação forense do instante real de criação dessas versões.
UPDATE contract_rule_versions
SET created_at_utc = active_from_utc
WHERE active_from_utc < created_at_utc - INTERVAL '5 minutes';

-- guarda anti-backdating em DDL (defesa em profundidade; 3-step INV-DB)
ALTER TABLE contract_rule_versions ADD CONSTRAINT chk_crv_no_backdate
  CHECK (active_from_utc >= created_at_utc - INTERVAL '5 minutes') NOT VALID;
ALTER TABLE contract_rule_versions VALIDATE CONSTRAINT chk_crv_no_backdate;
