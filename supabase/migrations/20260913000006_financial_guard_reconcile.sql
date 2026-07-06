-- =============================================================================
-- Migration: Financial Guard P6/6 — Reconciliation (deferred true-up + drift)
-- Purpose:   reconcile_financial_guard(): recomputes the expected accrual for
--            every capped contract over the current + previous UTC month and
--            corrects divergence. Closes the deferred path (55P03 rows whose
--            cap check was skipped under lock contention) and detects any
--            accounting drift (design §6.5 — without this, deferred rows are
--            a permanent hole).
--
-- Expected formula (matches the amend-RPC seed semantics):
--   expected = Σ nested fine_cents of the month's penal rows
--              (bucket = sealed cap_month_utc when present — INV-15 —
--               else date_trunc(month, occurred_at_utc): deferred and
--               capless-epoch rows)
--            − Σ financial_guard_credits of those sanctions
--   Known conservative bias: fines annulled while the contract was capless
--   leave no credit marker — expected over-counts them (more protection for
--   the payer); flagged here as drift for human review, never silently cut.
--
-- Design:    forensic_records/plans/20260704_financial_guard_architecture_plan.md §6.5
-- Invariants: INV-4, INV-6, INV-15, INV-16 (bounded hourly scan, no dedicated
--             JSONB index on the hot partitioned ledger — future knob),
--             INV-22 (org-scoped), lock order contracts → accrual.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.reconcile_financial_guard(
  p_organization_id UUID DEFAULT NULL
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_corrections INT := 0;
  v_month       DATE;
  v_expected    BIGINT;
  v_accrued     BIGINT;
  rec           RECORD;
BEGIN
  FOR rec IN
    SELECT c.id AS contract_id, c.organization_id, c.monthly_penalty_cap_cents
      FROM public.contracts c
     WHERE c.monthly_penalty_cap_cents IS NOT NULL
       AND (p_organization_id IS NULL OR c.organization_id = p_organization_id)
  LOOP
    -- LOCK ORDER INVARIANT: contracts row BEFORE accrual (same as engine).
    PERFORM 1 FROM public.contracts c
     WHERE c.id = rec.contract_id AND c.organization_id = rec.organization_id
       FOR UPDATE;

    FOR v_month IN
      SELECT (date_trunc('month', now() AT TIME ZONE 'UTC'))::DATE
      UNION
      SELECT (date_trunc('month', now() AT TIME ZONE 'UTC') - INTERVAL '1 month')::DATE
    LOOP
      SELECT
        GREATEST(
          COALESCE(SUM((l.payload -> 'verdict_evidence' ->> 'fine_cents')::BIGINT), 0)
          - COALESCE((
              SELECT SUM(fc.credited_cents)
                FROM public.financial_guard_credits fc
                JOIN public.sla_audit_ledger_v2 s
                  ON s.organization_id = fc.organization_id
                 AND s.id = fc.sanction_ledger_entry_id
               WHERE fc.organization_id = rec.organization_id
                 AND s.contract_id = rec.contract_id
                 AND COALESCE((s.payload ->> 'cap_month_utc')::DATE,
                              (date_trunc('month', s.occurred_at_utc AT TIME ZONE 'UTC'))::DATE)
                     = v_month
            ), 0),
          0)
        INTO v_expected
        FROM public.sla_audit_ledger_v2 l
       WHERE l.organization_id = rec.organization_id
         AND l.contract_id = rec.contract_id
         AND l.type IN ('SANCTION_RECOMMENDED', 'NO_SHOW_PENALTY')
         AND COALESCE((l.payload ->> 'cap_month_utc')::DATE,
                      (date_trunc('month', l.occurred_at_utc AT TIME ZONE 'UTC'))::DATE)
             = v_month;

      SELECT a.accrued_cents INTO v_accrued
        FROM public.contract_penalty_monthly_accrual a
       WHERE a.organization_id = rec.organization_id
         AND a.contract_id = rec.contract_id
         AND a.month_utc = v_month;

      IF v_expected = COALESCE(v_accrued, 0) THEN
        CONTINUE; -- in sync (idempotent re-run lands here)
      END IF;
      IF v_accrued IS NULL AND v_expected = 0 THEN
        CONTINUE; -- no row, nothing owed: do not materialize empty buckets
      END IF;

      INSERT INTO public.contract_penalty_monthly_accrual
          (organization_id, contract_id, month_utc, accrued_cents, cap_cents_snapshot)
      VALUES (rec.organization_id, rec.contract_id, v_month, v_expected,
              rec.monthly_penalty_cap_cents)
      ON CONFLICT (organization_id, contract_id, month_utc) DO UPDATE
        SET accrued_cents = EXCLUDED.accrued_cents,
            updated_at_utc = now();

      INSERT INTO public.system_audit_log
          (event_type, severity, actor_type, source, organization_id, payload)
      VALUES ('FINANCIAL_GUARD_DRIFT', 'critical', 'SYSTEM', 'financial_guard_reconcile',
              rec.organization_id,
              jsonb_build_object(
                'contract_id', rec.contract_id, 'month_utc', v_month,
                'accrued_before_cents', COALESCE(v_accrued, 0),
                'expected_cents', v_expected, 'corrected', true));

      v_corrections := v_corrections + 1;
    END LOOP;
  END LOOP;

  RETURN v_corrections;
END;
$$;

-- service_role only. REVOKE FROM PUBLIC strips service_role's implicit
-- EXECUTE — explicit re-grant is mandatory.
REVOKE ALL ON FUNCTION public.reconcile_financial_guard(UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reconcile_financial_guard(UUID) TO service_role;

-- Hourly reconciliation. Guard: pg_cron only exists on Supabase Cloud (INV-23);
-- local dev invokes the RPC manually.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'cron') THEN
    PERFORM cron.schedule(
      'financial-guard-reconcile',
      '30 * * * *',
      $cron$ SELECT public.reconcile_financial_guard(); $cron$
    );
  END IF;
END;
$$;
