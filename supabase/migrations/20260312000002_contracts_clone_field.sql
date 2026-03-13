-- Migration: 20260312000002_contracts_clone_field
-- Sprint 5.11 — Anti-Fatigue & UX Excellence
-- Adiciona campo de auditoria para rastreabilidade de contratos clonados.
--
-- Intencionalmente TEXT (não UUID FK): campo de auditoria imutável.
-- O contrato-fonte pode ser encerrado ou até excluído no futuro sem
-- quebrar a referência histórica. A integridade referencial aqui seria
-- um anti-pattern para dados de auditoria.

ALTER TABLE contracts
  ADD COLUMN IF NOT EXISTS cloned_from_contract_id TEXT;

COMMENT ON COLUMN contracts.cloned_from_contract_id IS
  'UUID do contrato-fonte quando este foi criado via clonagem. '
  'Campo de auditoria imutável — NULL indica contrato criado diretamente.';
