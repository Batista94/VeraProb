-- =============================================================================
-- Migration: Dispute SLA Timer (Aging) + Retraction Provenance + ledger widening
-- Invariants: INV-6, INV-15, INV-23, INV-DB.
-- =============================================================================
ALTER TABLE public.organizations
  ADD COLUMN IF NOT EXISTS dispute_resolution_sla_days INT NOT NULL DEFAULT 5;
ALTER TABLE public.contracts
  ADD COLUMN IF NOT EXISTS dispute_resolution_sla_days INT;

ALTER TABLE public.sanction_review_queue ADD COLUMN IF NOT EXISTS disputed_at TIMESTAMPTZ;
ALTER TABLE public.sanction_review_queue ADD COLUMN IF NOT EXISTS disputed_by UUID;
ALTER TABLE public.sanction_review_queue ADD COLUMN IF NOT EXISTS resolution_due_at TIMESTAMPTZ;

COMMENT ON COLUMN public.sanction_review_queue.disputed_by IS
  'Who opened the dispute. NEVER cleared on retract (INV-23). The retract fact records the canceller separately.';

CREATE OR REPLACE FUNCTION public._resolve_dispute_sla_days(
  p_organization_id UUID, p_contract_id TEXT)
RETURNS INT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE v_org INT; v_contract INT; v_uuid UUID;
BEGIN
  SELECT dispute_resolution_sla_days INTO v_org FROM public.organizations WHERE id = p_organization_id;
  BEGIN v_uuid := p_contract_id::uuid; EXCEPTION WHEN others THEN v_uuid := NULL; END;
  IF v_uuid IS NOT NULL THEN
    SELECT dispute_resolution_sla_days INTO v_contract
      FROM public.contracts WHERE id = v_uuid AND organization_id = p_organization_id;
  END IF;
  RETURN COALESCE(v_contract, v_org, 5);
END;
$$;
REVOKE ALL ON FUNCTION public._resolve_dispute_sla_days(UUID, TEXT)
  FROM PUBLIC, anon, authenticated, service_role;

-- SLA breach sweep index
CREATE INDEX IF NOT EXISTS idx_srq_dispute_sla
  ON public.sanction_review_queue (organization_id, resolution_due_at)
  WHERE status = 'disputed' AND resolution_due_at IS NOT NULL;

-- M-qa: idempotency index for the cron's NOT EXISTS subquery
CREATE INDEX IF NOT EXISTS idx_ledger_sla_breached_queue
  ON public.sla_audit_ledger_v2 ((payload ->> 'queue_entry_id'))
  WHERE type = 'DISPUTE_SLA_BREACHED';

-- ── H1: widen ledger type CHECK WITHOUT a no-constraint window ────────────────
-- Add the new superset as NOT VALID, validate, then drop the old. Never DROP-first.
ALTER TABLE public.sla_audit_ledger_v2
  ADD CONSTRAINT chk_ledger_type_v2 CHECK (type IN (
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
    'DUAL_CONTROL_THRESHOLD_CHANGED',
    -- Phase 10.6
    'DISPUTE_EVIDENCE_ATTACHED','DISPUTE_SLA_BREACHED','EVIDENCE_HASH_MISMATCH'
  )) NOT VALID;
ALTER TABLE public.sla_audit_ledger_v2 VALIDATE CONSTRAINT chk_ledger_type_v2;
ALTER TABLE public.sla_audit_ledger_v2 DROP CONSTRAINT IF EXISTS chk_ledger_type; -- INV-DB: zero-downtime-verified
-- Restore the canonical name: the constraint keeps its stable identity across
-- widenings so existing tests/contracts referencing `chk_ledger_type` never break.
-- RENAME CONSTRAINT is a catalog-only metadata change (no rewrite/validation window).
ALTER TABLE public.sla_audit_ledger_v2 RENAME CONSTRAINT chk_ledger_type_v2 TO chk_ledger_type;

-- ── Cron sweep: flag SLA-breached disputes (Q3: signal only, no status change) ─
-- M-qa: optional defense-in-depth unique index to harden against a concurrent
-- double-flag (signal-only fact, so a 23505 on the rare race is acceptable).
CREATE UNIQUE INDEX IF NOT EXISTS uq_ledger_sla_breach_once
  ON public.sla_audit_ledger_v2 (organization_id, (payload ->> 'queue_entry_id'))
  WHERE type = 'DISPUTE_SLA_BREACHED';

CREATE OR REPLACE FUNCTION public.flag_sla_breached_disputes()
RETURNS INT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE v_row public.sanction_review_queue; v_now TIMESTAMPTZ := now(); v_count INT := 0;
BEGIN
  FOR v_row IN
    SELECT * FROM public.sanction_review_queue
     WHERE status = 'disputed' AND resolution_due_at IS NOT NULL AND resolution_due_at < v_now
       AND NOT EXISTS (
         SELECT 1 FROM public.sla_audit_ledger_v2 l
          WHERE l.type = 'DISPUTE_SLA_BREACHED'
            AND l.organization_id = sanction_review_queue.organization_id
            AND l.payload ->> 'queue_entry_id' = sanction_review_queue.id::text)
     FOR UPDATE SKIP LOCKED
  LOOP
    INSERT INTO public.sla_audit_ledger_v2
      (organization_id, type, operator_id, set_id, contract_id, plan_version, payload, occurred_at_utc)
    VALUES (
      v_row.organization_id, 'DISPUTE_SLA_BREACHED', 'SYSTEM', v_row.set_id,
      v_row.contract_id::uuid, 0,
      jsonb_build_object(
        'queue_entry_id', v_row.id, 'resolution_due_at', v_row.resolution_due_at,
        'breached_at', v_now, 'disputed_by', v_row.disputed_by,
        'disputed_at', v_row.disputed_at,
        'days_overdue', EXTRACT(DAY FROM (v_now - v_row.resolution_due_at))),
      v_now
    )
    ON CONFLICT DO NOTHING;  -- harden the concurrent double-flag race
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$$;
REVOKE ALL ON FUNCTION public.flag_sla_breached_disputes() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.flag_sla_breached_disputes() TO service_role;
