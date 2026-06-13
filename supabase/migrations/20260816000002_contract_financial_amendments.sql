-- pr_scanner: ignore-regression
-- Council-reviewed (Sprint B SLA Versioning plan, approved 2026-06-12).
-- =============================================================================
-- Migration: Sprint B — Contract Financial Amendments
-- Purpose:   Append-only version history for contract financial terms
--            (financial_ceiling_cents / penalty_multiplier). Source of truth
--            for renegotiations; contracts row keeps a denormalized copy.
--
-- Invariants: INV-3 (append-only), INV-4 (BIGINT cents / INT bps — corrige a
--             impedância do float legado contracts.penalty_multiplier),
--             INV-6 (TIMESTAMPTZ), INV-15 (anti-backdating), INV-22 (RLS org).
-- Writes:    SECURITY DEFINER RPC amend_contract_financial_terms only
--            (no INSERT policy for authenticated — deny by RLS).
-- =============================================================================

CREATE TABLE IF NOT EXISTS contract_financial_amendments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id),
    contract_id TEXT NOT NULL,  -- contracts UUID as text (convention: contract_rule_sets)
    financial_ceiling_cents BIGINT NULL,  -- NULL = sem teto
    penalty_multiplier_bps INT NOT NULL
      CONSTRAINT chk_cfa_penalty_multiplier CHECK (penalty_multiplier_bps > 0),
    effective_at_utc TIMESTAMPTZ NOT NULL,
    amended_at_utc TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    amended_by_user_id UUID NOT NULL,
    notes TEXT
);

-- RLS: SELECT org-scoped; sem policy de INSERT/UPDATE/DELETE (deny-all p/ escrita
-- client-side — escrita exclusiva via RPC SECURITY DEFINER).
ALTER TABLE contract_financial_amendments ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Tenant Isolation: contract_financial_amendments"
    ON contract_financial_amendments FOR SELECT
    USING (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::UUID);

-- Trigger Imutabilidade (INV-3: append-only — bloqueia UPDATE/DELETE p/ todos os roles)
CREATE OR REPLACE FUNCTION trg_cfa_append_only_func() RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'INV-3: contract_financial_amendments is append-only';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_cfa_append_only
    BEFORE UPDATE OR DELETE ON contract_financial_amendments
    FOR EACH ROW EXECUTE FUNCTION trg_cfa_append_only_func();

-- Anti-backdating (INV-15). Tabela nova/vazia: VALIDATE é seguro aqui.
ALTER TABLE contract_financial_amendments ADD CONSTRAINT chk_cfa_no_backdate
    CHECK (effective_at_utc >= amended_at_utc - INTERVAL '5 minutes') NOT VALID;
ALTER TABLE contract_financial_amendments VALIDATE CONSTRAINT chk_cfa_no_backdate;

-- Timeline de amendments por contrato (leitura dominante: histórico no detalhe)
CREATE INDEX IF NOT EXISTS idx_cfa_org_contract
    ON contract_financial_amendments (organization_id, contract_id, effective_at_utc DESC);

-- Grants (INV-DATA-API-GRANT): leitura para authenticated; escrita só via RPC
-- (SECURITY DEFINER roda como owner). service_role explícito (lição: REVOKE
-- FROM PUBLIC remove acesso implícito do service_role).
REVOKE ALL ON TABLE public.contract_financial_amendments FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.contract_financial_amendments TO authenticated;
GRANT ALL ON TABLE public.contract_financial_amendments TO service_role;
