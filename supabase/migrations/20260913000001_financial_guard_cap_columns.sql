-- =============================================================================
-- Migration: Financial Guard P1/6 — Stop-Loss Cap Columns
-- Purpose:   Adds monthly_penalty_cap_cents to contracts (denormalized live
--            value read by the guard trigger) and to
--            contract_financial_amendments (append-only version history,
--            INV-3). NULL = no cap (guard passthrough).
--
-- Design:    forensic_records/plans/20260704_financial_guard_architecture_plan.md §1.1
-- Invariants: INV-4 (BIGINT cents), INV-3 (amendments append-only untouched),
--             INV-DB (3-step CHECK NOT VALID → VALIDATE — no blocking ALTER).
-- =============================================================================

-- contracts: live cap consumed by enforce_financial_guard() (migration 3/6)
ALTER TABLE public.contracts
    ADD COLUMN IF NOT EXISTS monthly_penalty_cap_cents BIGINT NULL;

ALTER TABLE public.contracts
    ADD CONSTRAINT chk_contracts_monthly_penalty_cap_positive
    CHECK (monthly_penalty_cap_cents IS NULL OR monthly_penalty_cap_cents > 0)
    NOT VALID;
ALTER TABLE public.contracts
    VALIDATE CONSTRAINT chk_contracts_monthly_penalty_cap_positive;

-- contract_financial_amendments: versioned mirror (SSOT of renegotiations)
ALTER TABLE public.contract_financial_amendments
    ADD COLUMN IF NOT EXISTS monthly_penalty_cap_cents BIGINT NULL;

ALTER TABLE public.contract_financial_amendments
    ADD CONSTRAINT chk_cfa_monthly_penalty_cap_positive
    CHECK (monthly_penalty_cap_cents IS NULL OR monthly_penalty_cap_cents > 0)
    NOT VALID;
ALTER TABLE public.contract_financial_amendments
    VALIDATE CONSTRAINT chk_cfa_monthly_penalty_cap_positive;

COMMENT ON COLUMN public.contracts.monthly_penalty_cap_cents IS
    'Financial Guard stop-loss: max penalty cents accrued per contract per UTC month. NULL = uncapped. INV-4 BIGINT cents.';
COMMENT ON COLUMN public.contract_financial_amendments.monthly_penalty_cap_cents IS
    'Versioned mirror of contracts.monthly_penalty_cap_cents at amendment time (INV-3 append-only history).';
