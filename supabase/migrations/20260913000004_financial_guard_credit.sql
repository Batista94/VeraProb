-- =============================================================================
-- Migration: Financial Guard P4/6 — Dispute Reversal Credit
-- Purpose:   Returns headroom to the monthly accumulator when a fine is
--            legally annulled: DISPUTE_ACCEPTED (dispute won) and
--            VERDICT_REFUSED (admin rejection — Council + user decision:
--            same legal semantics, fine never billed).
--            DISPUTE_OVERTURNED / DISPUTE_RETRACTED do NOT credit (fine
--            stands). Exactly-once via financial_guard_credits PK.
--
-- Design:    forensic_records/plans/20260704_financial_guard_architecture_plan.md §2.4
-- Invariants: INV-3 (ledger untouched), INV-4 (BIGINT cents),
--             INV-15 (month read from sealed cap_month_utc — never re-clamped),
--             INV-22 (lookups org-bound).
-- =============================================================================

CREATE OR REPLACE FUNCTION public.credit_financial_guard()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_queue_entry UUID;
  v_ledger_entry UUID;
  v_orig        RECORD;
  v_credit      BIGINT;
  v_month       DATE;
  v_before      BIGINT;
BEGIN
  -- Absent queue_entry_id = not a sanction-dispute context (e.g. legacy or
  -- synthetic rows). Fail-closed: no credit is granted, no error raised —
  -- real RPC writers (resolve_dispute, reject_sanction) always include it.
  BEGIN
    v_queue_entry := (NEW.payload ->> 'queue_entry_id')::UUID;
  EXCEPTION WHEN invalid_text_representation THEN
    RAISE EXCEPTION 'Financial guard credit: malformed queue_entry_id'
      USING ERRCODE = 'integrity_constraint_violation';
  END;
  IF v_queue_entry IS NULL THEN
    RETURN NEW;
  END IF;

  -- Linkage chain (scenario #21): present-but-dangling at ANY link is data
  -- corruption — fail fast, never a silent no-op.
  SELECT q.ledger_entry_id INTO v_ledger_entry
    FROM public.sanction_review_queue q
   WHERE q.id = v_queue_entry AND q.organization_id = NEW.organization_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Financial guard credit: queue entry not found for organization'
      USING ERRCODE = 'integrity_constraint_violation';
  END IF;

  SELECT l.id, l.contract_id, l.payload INTO v_orig
    FROM public.sla_audit_ledger_v2 l
   WHERE l.organization_id = NEW.organization_id AND l.id = v_ledger_entry;
  IF NOT FOUND THEN
    -- Queue row exists but its sanction ledger row does not. A RAISE here
    -- would abort the dispute resolution itself (AFTER trigger) — a ledger
    -- anomaly must never make disputes unresolvable. Fail-closed for the
    -- credit (none granted), loud for forensics (drift event).
    -- QA/Security sign-off 2026-07-05 supersedes design §2.4 scenario #21
    -- for this sub-case only (no-op + CRITICAL drift instead of RAISE);
    -- dangling queue_entry_id above still fails fast.
    INSERT INTO public.system_audit_log
        (event_type, severity, actor_type, source, organization_id, payload)
    VALUES ('FINANCIAL_GUARD_DRIFT', 'critical', 'SYSTEM', 'financial_guard_credit',
            NEW.organization_id,
            jsonb_build_object(
              'queue_entry_id', v_queue_entry,
              'missing_sanction_ledger_entry_id', v_ledger_entry,
              'resolution_ledger_entry_id', NEW.id));
    RETURN NEW;
  END IF;

  -- Guard-inactive gate: no original_fine_cents means the guard did not
  -- process the debit (uncapped contract at the time, or deferred row not
  -- yet trued-up) — nothing was accrued, so nothing to credit. Legitimate
  -- no-op, distinct from the lookup-miss fail-fast above. Deferred rows that
  -- get annulled are surfaced by reconcile_financial_guard as drift.
  IF NOT (v_orig.payload ? 'original_fine_cents') THEN
    RETURN NEW;
  END IF;

  BEGIN
    v_credit := (v_orig.payload -> 'verdict_evidence' ->> 'fine_cents')::BIGINT;
    v_month  := (v_orig.payload ->> 'cap_month_utc')::DATE;
  EXCEPTION WHEN invalid_text_representation OR datetime_field_overflow THEN
    v_credit := NULL;
  END;
  IF v_credit IS NULL OR v_credit < 0 OR v_month IS NULL THEN
    RAISE EXCEPTION 'Financial guard credit: guard keys corrupted on original sanction'
      USING ERRCODE = 'integrity_constraint_violation';
  END IF;

  -- Exactly-once (scenario #20): PK (org, sanction_ledger_entry_id).
  INSERT INTO public.financial_guard_credits
      (organization_id, sanction_ledger_entry_id, credited_cents)
  VALUES (NEW.organization_id, v_orig.id, v_credit)
  ON CONFLICT (organization_id, sanction_ledger_entry_id) DO NOTHING;
  IF NOT FOUND THEN
    RETURN NEW;
  END IF;

  IF v_credit = 0 THEN
    RETURN NEW; -- fully-truncated fine: marker recorded, nothing to reverse
  END IF;

  -- LOCK ORDER INVARIANT: contracts row BEFORE accrual table (same order as
  -- the debit engine — anti-deadlock). No custom lock_timeout here: a RAISE
  -- inside this AFTER trigger would abort the entire dispute resolution
  -- transaction. Credits are rare; full serialization is acceptable.
  PERFORM 1 FROM public.contracts c
   WHERE c.id = v_orig.contract_id AND c.organization_id = NEW.organization_id
     FOR UPDATE;

  SELECT a.accrued_cents INTO v_before
    FROM public.contract_penalty_monthly_accrual a
   WHERE a.organization_id = NEW.organization_id
     AND a.contract_id = v_orig.contract_id
     AND a.month_utc = v_month;

  IF NOT FOUND THEN
    -- Guard processed the debit but its accrual row is gone: an annulled
    -- fine is still being charged — same failure class reconcile flags as
    -- critical (QA/Security sign-off 2026-07-05).
    INSERT INTO public.system_audit_log
        (event_type, severity, actor_type, source, organization_id, payload)
    VALUES ('FINANCIAL_GUARD_DRIFT', 'critical', 'SYSTEM', 'financial_guard_credit',
            NEW.organization_id,
            jsonb_build_object(
              'contract_id', v_orig.contract_id, 'month_utc', v_month,
              'missing_accrual_row', true, 'credited_cents', v_credit,
              'sanction_ledger_entry_id', v_orig.id));
    RETURN NEW;
  END IF;

  UPDATE public.contract_penalty_monthly_accrual
     SET accrued_cents = GREATEST(accrued_cents - v_credit, 0),
         updated_at_utc = now()
   WHERE organization_id = NEW.organization_id
     AND contract_id = v_orig.contract_id
     AND month_utc = v_month;
  -- cap_reached_at_utc is NEVER cleared: the breach happened; the historical
  -- fact stands (INV-18). No CAP_REACHED re-emission either.

  IF v_before < v_credit THEN
    INSERT INTO public.system_audit_log
        (event_type, severity, actor_type, source, organization_id, payload)
    VALUES ('FINANCIAL_GUARD_DRIFT', 'warning', 'SYSTEM', 'financial_guard_credit',
            NEW.organization_id,
            jsonb_build_object(
              'contract_id', v_orig.contract_id, 'month_utc', v_month,
              'accrued_before_cents', v_before, 'credited_cents', v_credit,
              'clamped_to_zero', true,
              'sanction_ledger_entry_id', v_orig.id));
  END IF;

  RETURN NEW;
END;
$$;

-- AFTER trigger: does not mutate NEW; runs alongside trg_enqueue_verdict_webhooks
-- (both types are also in the webhook IF-list — independent concerns).
CREATE TRIGGER trg_financial_guard_credit
  AFTER INSERT ON public.sla_audit_ledger_v2
  FOR EACH ROW
  WHEN (NEW.type IN ('DISPUTE_ACCEPTED', 'VERDICT_REFUSED'))
  EXECUTE FUNCTION public.credit_financial_guard();
