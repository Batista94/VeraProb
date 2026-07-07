-- =============================================================================
-- Migration: Financial Guard Fail-Closed Patch
-- Purpose:   Fixes the timeout branch in `enforce_financial_guard` to seal the
--            fine as 0 (fail-closed) when the lock is unavailable, avoiding
--            over-billing. Adds `cap_month_utc` to the deferred payload to
--            prevent crashes in `credit_financial_guard`. Fixes 
--            `reconcile_financial_guard` to clamp expected accrual to the cap,
--            preventing historic overbilling from being canonized.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.enforce_financial_guard()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_claims        JSONB;
  v_fine          BIGINT;
  v_cap           BIGINT;
  v_tolerance     INT;
  v_now           TIMESTAMPTZ := now();
  v_bucket        TIMESTAMPTZ;
  v_month         DATE;
  v_accrued       BIGINT;
  v_remaining     BIGINT;
  v_applied       BIGINT;
  v_prev_timeout  TEXT;
  v_guard_keys    TEXT[] := ARRAY[
    'original_fine_cents','cap_truncated','cap_remaining_before_cents',
    'cap_check_deferred','cap_month_utc'];
BEGIN
  v_claims := auth.jwt();
  IF v_claims IS NOT NULL AND (v_claims ->> 'role') IS DISTINCT FROM 'service_role' THEN
    IF (v_claims -> 'app_metadata' ->> 'org_id') IS DISTINCT FROM NEW.organization_id::text THEN
      RAISE EXCEPTION 'Financial guard: organization claim mismatch'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  BEGIN
    v_fine := (NEW.payload -> 'verdict_evidence' ->> 'fine_cents')::BIGINT;
  EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
    RAISE EXCEPTION 'Financial guard: malformed verdict_evidence.fine_cents'
      USING ERRCODE = 'integrity_constraint_violation';
  END;

  IF v_fine IS NULL OR v_fine <= 0 THEN
    IF NEW.payload ?| v_guard_keys THEN
      NEW.payload := NEW.payload - v_guard_keys;
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.contract_id IS NULL THEN
    RAISE EXCEPTION 'Financial guard: billable sanction requires contract_id'
      USING ERRCODE = 'integrity_constraint_violation';
  END IF;

  SELECT c.monthly_penalty_cap_cents INTO v_cap
    FROM public.contracts c
   WHERE c.id = NEW.contract_id
     AND c.organization_id = NEW.organization_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Financial guard: contract not found for organization'
      USING ERRCODE = 'integrity_constraint_violation';
  END IF;
  IF v_cap IS NULL THEN
    IF NEW.payload ?| v_guard_keys THEN
      NEW.payload := NEW.payload - v_guard_keys;
    END IF;
    RETURN NEW;
  END IF;

  v_prev_timeout := current_setting('lock_timeout');
  PERFORM set_config('lock_timeout', '2s', true);
  BEGIN
    SELECT c.monthly_penalty_cap_cents INTO v_cap
      FROM public.contracts c
     WHERE c.id = NEW.contract_id
       AND c.organization_id = NEW.organization_id
       FOR UPDATE;
  EXCEPTION WHEN lock_not_available THEN
    PERFORM set_config('lock_timeout', v_prev_timeout, true);
    
    -- Spoof clock for month (same math as Phase E)
    SELECT o.clock_drift_tolerance_s INTO v_tolerance
      FROM public.organizations o WHERE o.id = NEW.organization_id;
    v_tolerance := COALESCE(v_tolerance, 300);
    v_bucket := LEAST(
      GREATEST(NEW.occurred_at_utc, v_now - make_interval(secs => v_tolerance)),
      v_now + make_interval(secs => v_tolerance));
    v_month := (date_trunc('month', v_bucket AT TIME ZONE 'UTC'))::DATE;

    NEW.payload :=
      jsonb_set(NEW.payload - v_guard_keys, '{verdict_evidence,fine_cents}', to_jsonb(0::BIGINT), true)
      || jsonb_build_object(
           'original_fine_cents', v_fine,
           'cap_truncated', true,
           'cap_check_deferred', true,
           'cap_month_utc', v_month);
           
    INSERT INTO public.system_audit_log
        (event_type, severity, actor_type, source, organization_id, payload)
    VALUES ('FINANCIAL_CAP_DEFERRED', 'critical', 'SYSTEM', 'financial_guard',
            NEW.organization_id,
            jsonb_build_object(
              'contract_id', NEW.contract_id,
              'month_utc', v_month,
              'original_fine_cents', v_fine,
              'deferred_ledger_entry_id', NEW.id));
              
    RETURN NEW;
  END;
  PERFORM set_config('lock_timeout', v_prev_timeout, true);

  IF v_cap IS NULL THEN
    IF NEW.payload ?| v_guard_keys THEN
      NEW.payload := NEW.payload - v_guard_keys;
    END IF;
    RETURN NEW;
  END IF;

  SELECT o.clock_drift_tolerance_s INTO v_tolerance
    FROM public.organizations o WHERE o.id = NEW.organization_id;
  v_tolerance := COALESCE(v_tolerance, 300);
  v_bucket := LEAST(
    GREATEST(NEW.occurred_at_utc, v_now - make_interval(secs => v_tolerance)),
    v_now + make_interval(secs => v_tolerance));
  v_month := (date_trunc('month', v_bucket AT TIME ZONE 'UTC'))::DATE;

  INSERT INTO public.contract_penalty_monthly_accrual
      (organization_id, contract_id, month_utc, accrued_cents, cap_cents_snapshot)
  VALUES (NEW.organization_id, NEW.contract_id, v_month, 0, v_cap)
  ON CONFLICT (organization_id, contract_id, month_utc) DO NOTHING;

  SELECT a.accrued_cents INTO v_accrued
    FROM public.contract_penalty_monthly_accrual a
   WHERE a.organization_id = NEW.organization_id
     AND a.contract_id = NEW.contract_id
     AND a.month_utc = v_month;

  v_remaining := GREATEST(v_cap - v_accrued, 0);
  v_applied   := LEAST(v_fine, v_remaining);

  NEW.payload :=
    jsonb_set(NEW.payload, '{verdict_evidence,fine_cents}', to_jsonb(v_applied), true)
    || jsonb_build_object(
         'original_fine_cents',        v_fine,
         'cap_truncated',              v_applied < v_fine,
         'cap_remaining_before_cents', v_remaining,
         'cap_check_deferred',         false,
         'cap_month_utc',              v_month);

  IF v_applied > 0 THEN
    UPDATE public.contract_penalty_monthly_accrual
       SET accrued_cents = accrued_cents + v_applied,
           updated_at_utc = v_now
     WHERE organization_id = NEW.organization_id
       AND contract_id = NEW.contract_id
       AND month_utc = v_month;
    v_accrued := v_accrued + v_applied;
  END IF;

  IF v_accrued >= (v_cap * 80 + 50) / 100 THEN
    UPDATE public.contract_penalty_monthly_accrual
       SET warned_at_utc = v_now
     WHERE organization_id = NEW.organization_id
       AND contract_id = NEW.contract_id
       AND month_utc = v_month
       AND warned_at_utc IS NULL;
    IF FOUND THEN
      INSERT INTO public.system_audit_log
          (event_type, severity, actor_type, source, organization_id, payload)
      VALUES ('FINANCIAL_CAP_WARNING', 'warning', 'SYSTEM', 'financial_guard',
              NEW.organization_id,
              jsonb_build_object(
                'contract_id', NEW.contract_id, 'month_utc', v_month,
                'cap_cents', v_cap, 'accrued_cents', v_accrued));
      INSERT INTO public.sla_audit_ledger_v2
          (organization_id, occurred_at_utc, type, contract_id, payload)
      VALUES (NEW.organization_id, v_now, 'FINANCIAL_CAP_WARNING', NEW.contract_id,
              jsonb_build_object(
                'contract_id', NEW.contract_id, 'month_utc', v_month,
                'cap_cents', v_cap, 'accrued_cents', v_accrued));
    END IF;
  END IF;

  IF v_accrued >= v_cap THEN
    UPDATE public.contract_penalty_monthly_accrual
       SET cap_reached_at_utc = v_now
     WHERE organization_id = NEW.organization_id
       AND contract_id = NEW.contract_id
       AND month_utc = v_month
       AND cap_reached_at_utc IS NULL;
    IF FOUND THEN
      INSERT INTO public.system_audit_log
          (event_type, severity, actor_type, source, organization_id, payload)
      VALUES ('FINANCIAL_CAP_REACHED', 'critical', 'SYSTEM', 'financial_guard',
              NEW.organization_id,
              jsonb_build_object(
                'contract_id', NEW.contract_id, 'month_utc', v_month,
                'cap_cents', v_cap,
                'breaching_ledger_entry_id', NEW.id,
                'original_fine_cents', v_fine,
                'applied_fine_cents', v_applied));
      INSERT INTO public.sla_audit_ledger_v2
          (organization_id, occurred_at_utc, type, contract_id, payload)
      VALUES (NEW.organization_id, v_now, 'FINANCIAL_CAP_REACHED', NEW.contract_id,
              jsonb_build_object(
                'contract_id', NEW.contract_id, 'month_utc', v_month,
                'cap_cents', v_cap,
                'breaching_ledger_entry_id', NEW.id,
                'original_fine_cents', v_fine,
                'applied_fine_cents', v_applied));
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

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
  v_clamped     BOOLEAN;
  rec           RECORD;
BEGIN
  FOR rec IN
    SELECT c.id AS contract_id, c.organization_id, c.monthly_penalty_cap_cents
      FROM public.contracts c
     WHERE c.monthly_penalty_cap_cents IS NOT NULL
       AND (p_organization_id IS NULL OR c.organization_id = p_organization_id)
  LOOP
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

      v_clamped := false;
      IF v_expected > rec.monthly_penalty_cap_cents THEN
        v_expected := rec.monthly_penalty_cap_cents;
        v_clamped := true;
      END IF;

      SELECT a.accrued_cents INTO v_accrued
        FROM public.contract_penalty_monthly_accrual a
       WHERE a.organization_id = rec.organization_id
         AND a.contract_id = rec.contract_id
         AND a.month_utc = v_month;

      IF v_expected = COALESCE(v_accrued, 0) THEN
        CONTINUE;
      END IF;
      IF v_accrued IS NULL AND v_expected = 0 THEN
        CONTINUE;
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
              jsonb_strip_nulls(jsonb_build_object(
                'contract_id', rec.contract_id, 'month_utc', v_month,
                'accrued_before_cents', COALESCE(v_accrued, 0),
                'expected_cents', v_expected, 'corrected', true,
                'overshoot_clamped', CASE WHEN v_clamped THEN true ELSE NULL END)));

      v_corrections := v_corrections + 1;
    END LOOP;
  END LOOP;

  RETURN v_corrections;
END;
$$;

-- Test-only function to force lock contention in tests
CREATE OR REPLACE FUNCTION public.test_hold_financial_guard_lock(
  p_organization_id UUID,
  p_contract_id UUID,
  p_seconds INT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  PERFORM 1 FROM public.contracts c
   WHERE c.id = p_contract_id AND c.organization_id = p_organization_id
     FOR UPDATE;
     
  PERFORM pg_sleep(p_seconds);
END;
$$;

-- Must revoke from public and grant to service_role explicitly
REVOKE ALL ON FUNCTION public.test_hold_financial_guard_lock(UUID, UUID, INT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.test_hold_financial_guard_lock(UUID, UUID, INT) TO service_role;
