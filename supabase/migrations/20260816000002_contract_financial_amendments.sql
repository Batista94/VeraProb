-- =============================================================================
-- Migration: Sprint B — Contract Financial Amendments
-- =============================================================================

CREATE TABLE IF NOT EXISTS contract_financial_amendments (
    id UUID PRIMARY KEY,
    organization_id UUID NOT NULL REFERENCES organizations(id),
    contract_id TEXT NOT NULL,
    financial_ceiling_cents BIGINT NULL,
    penalty_multiplier_bps INT CONSTRAINT chk_cfa_penalty_multiplier CHECK (penalty_multiplier_bps > 0),
    effective_at_utc TIMESTAMPTZ NOT NULL,
    amended_at_utc TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    amended_by_user_id UUID,
    notes TEXT
);

-- RLS
ALTER TABLE contract_financial_amendments ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Tenant Isolation: contract_financial_amendments"
    ON contract_financial_amendments FOR SELECT
    USING (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::UUID);

-- Trigger Imutabilidade
CREATE OR REPLACE FUNCTION trg_cfa_append_only_func() RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'INV-3: contract_financial_amendments is append-only';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_cfa_append_only
    BEFORE UPDATE OR DELETE ON contract_financial_amendments
    FOR EACH ROW EXECUTE FUNCTION trg_cfa_append_only_func();

-- Anti-backdating
ALTER TABLE contract_financial_amendments ADD CONSTRAINT chk_cfa_no_backdate
    CHECK (effective_at_utc >= amended_at_utc - INTERVAL '5 minutes') NOT VALID;
ALTER TABLE contract_financial_amendments VALIDATE CONSTRAINT chk_cfa_no_backdate;

-- Grants
SET ROLE supabase_admin;
REVOKE ALL ON TABLE public.contract_financial_amendments FROM public, anon, authenticated;
RESET ROLE;

REVOKE ALL ON TABLE contract_financial_amendments FROM public, anon, authenticated;
REVOKE UPDATE, DELETE ON TABLE contract_financial_amendments FROM authenticated;
GRANT SELECT, INSERT ON TABLE contract_financial_amendments TO authenticated;
GRANT ALL ON TABLE contract_financial_amendments TO service_role;
