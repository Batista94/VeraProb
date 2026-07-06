-- =============================================================================
-- Migration: Financial Guard P2/6 — O(1) Accrual Accumulator + Credit Marker
-- Purpose:   contract_penalty_monthly_accrual: one row per (org, contract,
--            UTC month) holding the running penalty total — the guard trigger
--            reads/writes it under the contracts row lock (O(1), no ledger
--            scan on the hot path).
--            financial_guard_credits: exactly-once marker for dispute
--            reversals (PK prevents double credit).
--
-- Design:    forensic_records/plans/20260704_financial_guard_architecture_plan.md §1.2, §1.2.1
-- Invariants: INV-2/INV-22 (RLS org via app_metadata.org_id, SELECT-only for
--             clients), INV-4 (BIGINT cents), INV-6 (TIMESTAMPTZ),
--             INV-DATA-API-GRANT (explicit grants).
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.contract_penalty_monthly_accrual (
    organization_id   UUID NOT NULL REFERENCES public.organizations(id),
    contract_id       UUID NOT NULL REFERENCES public.contracts(id),
    month_utc         DATE NOT NULL,
    accrued_cents     BIGINT NOT NULL DEFAULT 0
        CONSTRAINT chk_cpma_accrued_non_negative CHECK (accrued_cents >= 0),
    cap_cents_snapshot BIGINT NOT NULL
        CONSTRAINT chk_cpma_cap_snapshot_positive CHECK (cap_cents_snapshot > 0),
    cap_reached_at_utc TIMESTAMPTZ NULL,
    warned_at_utc      TIMESTAMPTZ NULL,
    updated_at_utc     TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (organization_id, contract_id, month_utc)
);

COMMENT ON TABLE public.contract_penalty_monthly_accrual IS
    'Financial Guard O(1) accumulator. LOCK ORDER INVARIANT: writers MUST '
    'acquire contracts row lock (SELECT ... FOR UPDATE) BEFORE touching this '
    'table. Never lock in the opposite order — deadlock. Design §1.2.';

CREATE TABLE IF NOT EXISTS public.financial_guard_credits (
    organization_id          UUID NOT NULL REFERENCES public.organizations(id),
    sanction_ledger_entry_id UUID NOT NULL,
    credited_cents           BIGINT NOT NULL
        CONSTRAINT chk_fgc_credited_non_negative CHECK (credited_cents >= 0),
    credited_at_utc          TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (organization_id, sanction_ledger_entry_id)
);

COMMENT ON TABLE public.financial_guard_credits IS
    'Exactly-once credit marker: PK (org, sanction_ledger_entry_id) makes '
    'dispute-reversal credit idempotent (ON CONFLICT DO NOTHING). Design §1.2.1.';

-- ── RLS: SELECT-only for tenants, org-scoped via app_metadata.org_id ─────────
-- (legacy top-level organization_id claim does NOT exist — would silently
--  match NULL and return zero rows)
ALTER TABLE public.contract_penalty_monthly_accrual ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Tenant Isolation: contract_penalty_monthly_accrual"
    ON public.contract_penalty_monthly_accrual FOR SELECT
    USING (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::UUID);

ALTER TABLE public.financial_guard_credits ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Tenant Isolation: financial_guard_credits"
    ON public.financial_guard_credits FOR SELECT
    USING (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::UUID);

-- No INSERT/UPDATE/DELETE policies: writes happen only inside SECURITY DEFINER
-- trigger functions (migrations 3-4) running as owner.

-- ── Grants (INV-DATA-API-GRANT) ──────────────────────────────────────────────
-- REVOKE FROM PUBLIC strips service_role's implicit access — re-grant explicit.
REVOKE ALL ON TABLE public.contract_penalty_monthly_accrual FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.contract_penalty_monthly_accrual TO authenticated;
GRANT ALL ON TABLE public.contract_penalty_monthly_accrual TO service_role;

REVOKE ALL ON TABLE public.financial_guard_credits FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.financial_guard_credits TO authenticated;
GRANT ALL ON TABLE public.financial_guard_credits TO service_role;
