-- =============================================================================
-- Migration: dispute_open RPC — atomic dispute opening with SLA timer sealing
-- Purpose:   The ONLY path to transition a pending sanction to disputed status.
--            Atomically: row-locks the queue entry, re-checks pending status
--            (TOCTOU), appends SANCTION_DISPUTED ledger fact (INV-3), flips
--            status to disputed, and seals disputed_at / disputed_by /
--            resolution_due_at (computed via _compute_business_day_deadline).
--
-- Replaces the former non-atomic 2-round-trip pattern (append ledger +
-- updateStatus) used by the Dart handler, closing the TOCTOU race.
--
-- Invariants: INV-1, INV-2, INV-3, INV-6, INV-22, INV-23, INV-26.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.dispute_sanction(
  p_organization_id     UUID,
  p_queue_entry_id      UUID,
  p_disputed_by_user_id UUID,
  p_actor_email         TEXT,
  p_occurred_at_utc     TIMESTAMPTZ
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  v_jwt_org  TEXT;
  v_jwt_role TEXT;
  v_user     UUID;
  v_queue    public.sanction_review_queue;
  v_ledger_id UUID;
  v_sla_days INT;
  v_resolution_due TIMESTAMPTZ;
BEGIN
  -- ── Auth (anti-oracle: every failure → 42501, generic message; INV-26) ──────
  v_jwt_org := auth.jwt() -> 'app_metadata' ->> 'org_id';
  IF v_jwt_org IS NULL OR v_jwt_org::uuid <> p_organization_id THEN
    RAISE EXCEPTION 'Dispute rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  v_jwt_role := auth.jwt() -> 'app_metadata' ->> 'role';
  IF v_jwt_role IS NULL OR v_jwt_role NOT IN ('TENANT_ADMIN', 'AUDITOR') THEN
    RAISE EXCEPTION 'Dispute rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  v_user := (auth.jwt() ->> 'sub')::uuid;
  IF v_user IS NULL OR v_user <> p_disputed_by_user_id THEN
    RAISE EXCEPTION 'Dispute rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- ── Row lock + state check (TOCTOU closure) ─────────────────────────────────
  SELECT * INTO v_queue FROM public.sanction_review_queue
   WHERE id = p_queue_entry_id AND organization_id = p_organization_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Dispute rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF v_queue.status <> 'pending' THEN
    RAISE EXCEPTION 'This sanction has already been reviewed by another auditor.'
      USING ERRCODE = 'P0001', DETAIL = 'IdempotencyProcessingException';
  END IF;

  -- ── Compute SLA deadline (business days, INV-15) ────────────────────────────
  v_sla_days := public._resolve_dispute_sla_days(p_organization_id, v_queue.contract_id);
  v_resolution_due := public._compute_business_day_deadline(
    p_organization_id, p_occurred_at_utc::date, v_sla_days);

  -- ── Append SANCTION_DISPUTED fact to immutable ledger (INV-3) ───────────────
  INSERT INTO public.sla_audit_ledger_v2
    (organization_id, type, operator_id, set_id, contract_id, plan_version, payload, occurred_at_utc)
  VALUES (
    p_organization_id, 'SANCTION_DISPUTED', v_user::text, v_queue.set_id,
    v_queue.contract_id::uuid, 0,
    jsonb_build_object(
      'queue_entry_id', p_queue_entry_id,
      'disputed_by_user_id', v_user,
      'actor_email', p_actor_email,
      'verdict_evidence', v_queue.verdict_evidence,
      'resolution_due_at', v_resolution_due,
      'dispute_sla_days', v_sla_days
    ),
    p_occurred_at_utc
  )
  RETURNING id INTO v_ledger_id;

  -- ── Flip queue status + seal dispute provenance (INV-23) ────────────────────
  UPDATE public.sanction_review_queue
     SET status = 'disputed',
         reviewed_at = p_occurred_at_utc,
         reviewed_by = v_user,
         disputed_at = p_occurred_at_utc,          -- sealed (INV-23: NEVER cleared)
         disputed_by = v_user,                     -- sealed (INV-23: NEVER cleared)
         resolution_due_at = v_resolution_due       -- SLA timer (Q3)
   WHERE id = p_queue_entry_id AND organization_id = p_organization_id;

  RETURN jsonb_build_object(
    'ledger_entry_id', v_ledger_id,
    'status', 'disputed',
    'resolution_due_at', v_resolution_due
  );
END;
$$;

-- ── Grants ────────────────────────────────────────────────────────────────────
REVOKE ALL ON FUNCTION public.dispute_sanction(UUID, UUID, UUID, TEXT, TIMESTAMPTZ)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.dispute_sanction(UUID, UUID, UUID, TEXT, TIMESTAMPTZ)
  TO authenticated;
