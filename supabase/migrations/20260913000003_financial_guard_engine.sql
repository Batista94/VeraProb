-- =============================================================================
-- Migration: Financial Guard P3/6 — Core Engine (BEFORE INSERT trigger)
-- Purpose:   Monthly penalty stop-loss. Truncates the applied fine so the
--            per-contract UTC-month total never exceeds
--            contracts.monthly_penalty_cap_cents. The guard cuts the FINE,
--            never the forensic fact (INV-18): the ledger row is always
--            inserted; original_fine_cents is sealed in the payload.
--
-- Design:    forensic_records/plans/20260704_financial_guard_architecture_plan.md §2, §3
-- Invariants: INV-3 (append-only untouched), INV-4 (BIGINT cents),
--             INV-6 (UTC), INV-15 (deterministic replay: cap_month_utc sealed
--             at debit time), INV-16 (lock_timeout + deferred path — never
--             hold the pool hostage), INV-18 (fact preserved), INV-22 (claim
--             check before any lock).
-- =============================================================================

-- ── 1. Widen chk_ledger_type (v7 swap → canonical name preserved) ────────────
-- Adds FINANCIAL_CAP_REACHED + FINANCIAL_CAP_WARNING. Carries ALL v6 values
-- (23514 trap: DROP+ADD replaces the whole constraint).
ALTER TABLE public.sla_audit_ledger_v2
  ADD CONSTRAINT chk_ledger_type_v7 CHECK (type IN (
    'EXECUTION_BOUND','NO_SHOW_DECLARED','EVIDENCE_GAP_DECLARED','PLAN_DECLARED',
    'OCCURRENCE_REGISTERED','TRIP_INTERRUPTED','TRIP_CANCELLED','CONTRACT_CREATED',
    'CONTRACT_ACTIVATED','CONTRACT_CLOSED','CONTRACT_SUBMITTED_FOR_APPROVAL',
    'CONTRACT_ACCEPTED_BY_CONTRACTOR','SANCTION_RECOMMENDED','VERDICT_SEALED',
    'VERDICT_REFUSED','SANCTION_DISPUTED','DISPUTE_ACCEPTED','DISPUTE_OVERTURNED',
    'DISPUTE_RETRACTED','JUSTIFICATION_SUBMITTED','JUSTIFICATION_APPROVED',
    'JUSTIFICATION_REJECTED','SLA_JUSTIFICATION_SUBMITTED','SLA_JUSTIFICATION_EXPIRED',
    'TRANSIT_STARTED','COMPLETED_WITH_GAPS','EXECUTION_INHIBITED','UNKNOWN_EVENT',
    'MAX_TOLERANCE_DELAY','MAX_EVIDENCE_GAP','MIN_GEOFENCE_COVERAGE','NO_SHOW_PENALTY',
    'PEER_REVIEW_REQUESTED','PEER_REVIEW_DECLINED','PEER_REVIEW_EXPIRED',
    'DUAL_CONTROL_THRESHOLD_CHANGED','DISPUTE_EVIDENCE_ATTACHED','DISPUTE_SLA_BREACHED',
    'EVIDENCE_HASH_MISMATCH','DISPUTE_PORTAL_TOKEN_GENERATED','DISPUTE_PORTAL_TOKEN_ACCESSED',
    'DISPUTE_PORTAL_TOKEN_REVOKED','RULE_SCHEDULED','RULE_ACTIVATED','RULE_RETIRED',
    'CONTRACT_FINANCIAL_TERMS_AMENDED',
    'PORTAL_EVIDENCE_SUBMITTED','PORTAL_EVIDENCE_FINALIZED','PORTAL_EVIDENCE_HASH_MISMATCH',
    'PORTAL_EVIDENCE_MIME_MISMATCH','PORTAL_EVIDENCE_REJECTED',
    'PORTAL_EVIDENCE_AUDITOR_ACCEPTED','PORTAL_EVIDENCE_AUDITOR_REJECTED',
    'SANCTION_ACKNOWLEDGED',
    'PORTAL_JUSTIFICATION_SUBMITTED',
    -- Financial Guard (stop-loss cap)
    'FINANCIAL_CAP_REACHED','FINANCIAL_CAP_WARNING'
  )) NOT VALID; -- INV-DB: zero-downtime-verified (superset; existing rows conform)
ALTER TABLE public.sla_audit_ledger_v2 VALIDATE CONSTRAINT chk_ledger_type_v7;
ALTER TABLE public.sla_audit_ledger_v2 DROP CONSTRAINT IF EXISTS chk_ledger_type; -- INV-DB: zero-downtime-verified (CHECK swap)
ALTER TABLE public.sla_audit_ledger_v2 RENAME CONSTRAINT chk_ledger_type_v7 TO chk_ledger_type;

-- ── 2. Guard engine ──────────────────────────────────────────────────────────
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
  -- Guard-owned payload keys. Client-supplied values for these are forged
  -- provenance: stripped on passthrough, overwritten on the guarded path.
  v_guard_keys    TEXT[] := ARRAY[
    'original_fine_cents','cap_truncated','cap_remaining_before_cents',
    'cap_check_deferred','cap_month_utc'];
BEGIN
  -- Phase A — tenant claim check (INV-22), BEFORE any lock is taken.
  v_claims := auth.jwt();
  IF v_claims IS NOT NULL AND (v_claims ->> 'role') IS DISTINCT FROM 'service_role' THEN
    IF (v_claims -> 'app_metadata' ->> 'org_id') IS DISTINCT FROM NEW.organization_id::text THEN
      RAISE EXCEPTION 'Financial guard: organization claim mismatch'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  -- Phase B — extract the fine. Absent / non-positive = not a billable
  -- sanction: passthrough, but never let forged guard keys survive.
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

  -- Phase C — no-lock cap probe. Uncapped contract = passthrough (payload
  -- untouched when clean — byte-exact replay, INV-15).
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

  -- Phase D — lock-then-check. Bounded wait; on timeout take the deferred
  -- path (fine INTACT, row preserved, reconcile_financial_guard trues up).
  -- set_config(..., true) is tx-scoped and would leak into the caller's
  -- transaction — save and restore.
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
    NEW.payload := (NEW.payload - v_guard_keys)
      || jsonb_build_object('cap_check_deferred', true);
    RETURN NEW;
  END;
  PERFORM set_config('lock_timeout', v_prev_timeout, true);

  -- Cap may have been dropped between probe and lock.
  IF v_cap IS NULL THEN
    IF NEW.payload ?| v_guard_keys THEN
      NEW.payload := NEW.payload - v_guard_keys;
    END IF;
    RETURN NEW;
  END IF;

  -- Phase E — clock-spoof clamp (design §2.3.1). The BUCKET is clamped to
  -- [now-tol, now+tol]; the forensic occurred_at_utc is NEVER altered.
  SELECT o.clock_drift_tolerance_s INTO v_tolerance
    FROM public.organizations o WHERE o.id = NEW.organization_id;
  v_tolerance := COALESCE(v_tolerance, 300);
  v_bucket := LEAST(
    GREATEST(NEW.occurred_at_utc, v_now - make_interval(secs => v_tolerance)),
    v_now + make_interval(secs => v_tolerance));
  v_month := (date_trunc('month', v_bucket AT TIME ZONE 'UTC'))::DATE;

  -- Phase F — O(1) accrual under the contracts row lock.
  -- LOCK ORDER INVARIANT: contracts FOR UPDATE (Phase D) BEFORE this table.
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

  -- Phase G — payload mutation: unconditional overwrite (anti-forgery §4#15).
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

  -- Phase H — 80% early warning, once per contract-month.
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
      -- Companion ledger row: type is outside the penal WHEN (no recursion)
      -- and outside the webhook IF-list (no fan-out).
      INSERT INTO public.sla_audit_ledger_v2
          (organization_id, occurred_at_utc, type, contract_id, payload)
      VALUES (NEW.organization_id, v_now, 'FINANCIAL_CAP_WARNING', NEW.contract_id,
              jsonb_build_object(
                'contract_id', NEW.contract_id, 'month_utc', v_month,
                'cap_cents', v_cap, 'accrued_cents', v_accrued));
    END IF;
  END IF;

  -- Phase I — breach event, once per contract-month (idempotent).
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

-- BEFORE trigger on the partitioned parent propagates to p0..p3.
-- Name 'trg_financial_guard' sorts AFTER 'enforce_tenant_envelope_ledger'
-- ('e' < 't') — envelope validation always runs first.
CREATE TRIGGER trg_financial_guard
  BEFORE INSERT ON public.sla_audit_ledger_v2
  FOR EACH ROW
  WHEN (NEW.type IN ('SANCTION_RECOMMENDED', 'NO_SHOW_PENALTY'))
  EXECUTE FUNCTION public.enforce_financial_guard();

-- ── 3. Bootstrap backfill (design §5) ────────────────────────────────────────
-- Seeds the current-month accrual for capped contracts from fines already in
-- the ledger. Vacuous today (cap column just added, all NULL) but idempotent
-- and correct for any deploy order.
INSERT INTO public.contract_penalty_monthly_accrual
    (organization_id, contract_id, month_utc, accrued_cents, cap_cents_snapshot)
SELECT c.organization_id, c.id,
       (date_trunc('month', now() AT TIME ZONE 'UTC'))::DATE,
       COALESCE(SUM((l.payload -> 'verdict_evidence' ->> 'fine_cents')::BIGINT), 0),
       c.monthly_penalty_cap_cents
  FROM public.contracts c
  LEFT JOIN public.sla_audit_ledger_v2 l
    ON l.organization_id = c.organization_id
   AND l.contract_id = c.id
   AND l.type IN ('SANCTION_RECOMMENDED', 'NO_SHOW_PENALTY')
   AND l.occurred_at_utc >= date_trunc('month', now())
 WHERE c.monthly_penalty_cap_cents IS NOT NULL
 GROUP BY c.organization_id, c.id, c.monthly_penalty_cap_cents
ON CONFLICT (organization_id, contract_id, month_utc) DO NOTHING;
