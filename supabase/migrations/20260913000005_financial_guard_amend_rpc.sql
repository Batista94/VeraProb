-- =============================================================================
-- Migration: Financial Guard P5/6 — amend_contract_financial_terms v2 (6-arg)
-- Purpose:   Adds p_monthly_penalty_cap_cents to the financial amendment RPC.
--            Same param names/order as v1 + trailing DEFAULT NULL param:
--            existing named 5-arg PostgREST calls stay valid (PGRST202-safe);
--            the old overload is dropped so resolution stays unambiguous
--            (PGRST300-safe).
--            Anti-phantom-headroom seed: on a NULL→value cap transition the
--            current-month accrual is seeded from fines already in the ledger
--            minus credits — otherwise activating a cap mid-month would grant
--            full headroom ignoring the month's history.
--
-- Design:    forensic_records/plans/20260704_financial_guard_architecture_plan.md §5, §6-A
-- Invariants: INV-3 (amendments append-only), INV-4 (BIGINT cents),
--             INV-6 (UTC), INV-22 (org from JWT app_metadata).
-- Note: contracts row FOR UPDATE = same lock the guard engine takes — the
--       amend serializes with a sanction storm by construction (design §2.2),
--       and the LOCK ORDER INVARIANT (contracts BEFORE accrual) holds.
-- =============================================================================

DROP FUNCTION IF EXISTS public.amend_contract_financial_terms(UUID, BIGINT, INT, TIMESTAMPTZ, TEXT); -- INV-DB: zero-downtime-verified (signature swap, single overload kept; committed pgTAP updated in this same package)

CREATE OR REPLACE FUNCTION public.amend_contract_financial_terms(
  p_contract_id               UUID,
  p_financial_ceiling_cents   BIGINT,
  p_penalty_multiplier_bps    INT,
  p_effective_at_utc          TIMESTAMPTZ,
  p_notes                     TEXT,
  p_monthly_penalty_cap_cents BIGINT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller_org_id  UUID;
  v_caller_role    TEXT;
  v_amendment_id   UUID := gen_random_uuid();
  v_actor_id       UUID;
  v_prev_cap       BIGINT;
  v_month          DATE := (date_trunc('month', now() AT TIME ZONE 'UTC'))::DATE;
BEGIN
  v_caller_org_id := (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid;
  v_caller_role   := auth.jwt() -> 'app_metadata' ->> 'role';
  v_actor_id      := (auth.jwt() ->> 'sub')::uuid;

  IF v_caller_org_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: no organization context in JWT';
  END IF;

  IF v_caller_role <> 'TENANT_ADMIN' THEN
    RAISE EXCEPTION 'Unauthorized: TENANT_ADMIN role required';
  END IF;

  IF p_penalty_multiplier_bps IS NULL OR p_penalty_multiplier_bps <= 0 THEN
    RAISE EXCEPTION 'penalty_multiplier_bps must be a positive integer (INV-4)';
  END IF;

  IF p_monthly_penalty_cap_cents IS NOT NULL AND p_monthly_penalty_cap_cents <= 0 THEN
    RAISE EXCEPTION 'monthly_penalty_cap_cents must be positive or NULL (INV-4)';
  END IF;

  IF p_effective_at_utc < NOW() - INTERVAL '5 minutes' THEN
    RAISE EXCEPTION 'Anti-backdating violation: p_effective_at_utc is too far in the past';
  END IF;

  -- Row lock (replaces the v1 EXISTS probe): prev-cap read and the NULL→value
  -- seed must be atomic against the guard engine's lock-then-check.
  SELECT c.monthly_penalty_cap_cents INTO v_prev_cap
    FROM public.contracts c
   WHERE c.id = p_contract_id
     AND c.organization_id = v_caller_org_id
     FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Contract not found or unauthorized';
  END IF;

  INSERT INTO public.contract_financial_amendments (
    id, organization_id, contract_id, financial_ceiling_cents,
    penalty_multiplier_bps, effective_at_utc, amended_at_utc,
    amended_by_user_id, notes, monthly_penalty_cap_cents
  ) VALUES (
    v_amendment_id, v_caller_org_id, p_contract_id::text, p_financial_ceiling_cents,
    p_penalty_multiplier_bps, p_effective_at_utc, NOW(),
    v_actor_id, p_notes, p_monthly_penalty_cap_cents
  );

  -- Denormalized sync on contracts (amendment table is the versioned source
  -- of truth). penalty_multiplier is the legacy DOUBLE PRECISION column —
  -- INV-4 impedance: bps INT is canonical here; float derived for the engine.
  -- seal_contracts_forensic + bump_contracts_version triggers seal this UPDATE.
  UPDATE public.contracts
  SET financial_ceiling_cents   = p_financial_ceiling_cents,
      penalty_multiplier        = p_penalty_multiplier_bps / 10000.0,
      monthly_penalty_cap_cents = p_monthly_penalty_cap_cents
  WHERE id = p_contract_id
    AND organization_id = v_caller_org_id;

  -- Anti-phantom-headroom seed (design §5 applied where the gap is born):
  -- cap transitions NULL→value mid-month ⇒ the month's already-issued fines
  -- must pre-consume headroom. Seed = Σ nested fine_cents of this month's
  -- penal rows − Σ credits already granted for those sanctions.
  -- (Fines annulled while the contract was capless leave no credit marker —
  --  the seed over-counts those; reconcile_financial_guard flags the drift.)
  IF v_prev_cap IS NULL AND p_monthly_penalty_cap_cents IS NOT NULL THEN
    INSERT INTO public.contract_penalty_monthly_accrual
        (organization_id, contract_id, month_utc, accrued_cents, cap_cents_snapshot)
    SELECT v_caller_org_id, p_contract_id, v_month,
           GREATEST(
             COALESCE((
               SELECT SUM((l.payload -> 'verdict_evidence' ->> 'fine_cents')::BIGINT)
                 FROM public.sla_audit_ledger_v2 l
                WHERE l.organization_id = v_caller_org_id
                  AND l.contract_id = p_contract_id
                  AND l.type IN ('SANCTION_RECOMMENDED', 'NO_SHOW_PENALTY')
                  AND l.occurred_at_utc >= date_trunc('month', now())
             ), 0)
             - COALESCE((
               SELECT SUM(fc.credited_cents)
                 FROM public.financial_guard_credits fc
                 JOIN public.sla_audit_ledger_v2 s
                   ON s.organization_id = fc.organization_id
                  AND s.id = fc.sanction_ledger_entry_id
                WHERE fc.organization_id = v_caller_org_id
                  AND s.contract_id = p_contract_id
                  AND s.occurred_at_utc >= date_trunc('month', now())
             ), 0),
             0),
           p_monthly_penalty_cap_cents
    ON CONFLICT (organization_id, contract_id, month_utc) DO UPDATE
      SET accrued_cents      = EXCLUDED.accrued_cents,
          cap_cents_snapshot = EXCLUDED.cap_cents_snapshot,
          updated_at_utc     = now();
  END IF;

  INSERT INTO public.sla_audit_ledger_v2
    (organization_id, type, operator_id, set_id, contract_id,
     plan_version, payload, occurred_at_utc)
  VALUES (
    v_caller_org_id, 'CONTRACT_FINANCIAL_TERMS_AMENDED', v_actor_id::text,
    p_contract_id::text, p_contract_id, 0,
    jsonb_build_object(
      'amendment_id', v_amendment_id,
      'financial_ceiling_cents', p_financial_ceiling_cents,
      'penalty_multiplier_bps', p_penalty_multiplier_bps,
      'monthly_penalty_cap_cents', p_monthly_penalty_cap_cents,
      'effective_at_utc', p_effective_at_utc,
      'actor_id', v_actor_id
    ),
    NOW()
  );

  RETURN v_amendment_id;
END;
$$;

REVOKE ALL ON FUNCTION public.amend_contract_financial_terms(UUID, BIGINT, INT, TIMESTAMPTZ, TEXT, BIGINT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.amend_contract_financial_terms(UUID, BIGINT, INT, TIMESTAMPTZ, TEXT, BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.amend_contract_financial_terms(UUID, BIGINT, INT, TIMESTAMPTZ, TEXT, BIGINT) TO service_role;
