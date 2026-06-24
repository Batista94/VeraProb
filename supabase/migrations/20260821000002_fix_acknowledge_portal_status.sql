-- =============================================================================
-- Migration: fix_acknowledge_portal_status — Issue 4
-- Purpose:   Allows "De Acordo" (acknowledgement) via portal to be accepted
--            when the queue status is either 'applied' or 'disputed'. Previously,
--            if a carrier generated a portal link while 'disputed', they could
--            not surrender and accept the sanction without counter-evidence.
--
-- Pattern:   CREATE OR REPLACE FUNCTION (Zero-downtime, INV-DB).
--            No locking changes, no signature changes.
--
-- Council: Architect ✅ · Senior ✅ · QA-Security ✅ · Business ✅ · Lead ✅
-- Invariants: INV-1, INV-26, INV-22.
-- Depends on: 20260817000005_portal_submission_rpcs_ledger.sql
-- =============================================================================

SET client_min_messages TO 'WARNING';

CREATE OR REPLACE FUNCTION public.acknowledge_via_portal(
  p_token         UUID,
  p_snapshot_hash TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_token   public.dispute_portal_tokens;
  v_queue   public.sanction_review_queue;
  v_served  TEXT;
  v_ack     UUID;
  v_now     TIMESTAMPTZ := NOW();
BEGIN
  -- Timing normalization (anti side-channel; same idiom as read_dispute_portal).
  PERFORM pg_advisory_xact_lock(hashtextextended(p_token::text, 0));

  IF p_snapshot_hash IS NULL OR p_snapshot_hash !~ '^[a-f0-9]{64}$' THEN
    RAISE EXCEPTION 'Acknowledgement rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_token FROM public.dispute_portal_tokens
   WHERE token = p_token FOR UPDATE;
  IF NOT FOUND
     OR v_token.revoked_at_utc IS NOT NULL
     OR v_now > v_token.expires_at_utc
  THEN
    RAISE EXCEPTION 'Acknowledgement rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_queue FROM public.sanction_review_queue
   WHERE id = v_token.queue_entry_id AND organization_id = v_token.organization_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Acknowledgement rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Idempotent: this token already acknowledged → return the existing record.
  IF v_queue.status = 'acknowledged' THEN
    SELECT id INTO v_ack FROM public.sanction_acknowledgements
     WHERE queue_entry_id = v_token.queue_entry_id
       AND acknowledged_via_token_id = v_token.id
     ORDER BY acknowledged_at_utc DESC LIMIT 1;
    IF v_ack IS NOT NULL THEN
      RETURN v_ack;
    END IF;
    RAISE EXCEPTION 'Acknowledgement rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- De Acordo is meaningful once the sanction is applied, OR when it is disputed
  -- and the carrier decides to surrender without submitting counter-evidence.
  IF v_queue.status NOT IN ('applied', 'disputed') THEN
    RAISE EXCEPTION 'Acknowledgement rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Hash binding: the served snapshot hash recorded at first portal access.
  SELECT payload ->> 'snapshot_hash' INTO v_served
    FROM public.sla_audit_ledger_v2
   WHERE organization_id = v_token.organization_id
     AND type = 'DISPUTE_PORTAL_TOKEN_ACCESSED'
     AND payload ->> 'token_id' = v_token.id::text
   ORDER BY occurred_at_utc DESC LIMIT 1;
  IF v_served IS NULL OR v_served <> p_snapshot_hash THEN
    RAISE EXCEPTION 'Acknowledgement rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  INSERT INTO public.sanction_acknowledgements
    (organization_id, queue_entry_id, snapshot_hash_acknowledged,
     acknowledgement_method, acknowledged_via_token_id, acknowledged_at_utc)
  VALUES
    (v_token.organization_id, v_token.queue_entry_id, p_snapshot_hash,
     'PORTAL_TOKEN', v_token.id, v_now)
  RETURNING id INTO v_ack;

  UPDATE public.sanction_review_queue
     SET status = 'acknowledged'
   WHERE id = v_token.queue_entry_id AND organization_id = v_token.organization_id;

  INSERT INTO public.sla_audit_ledger_v2
    (organization_id, type, operator_id, set_id, contract_id, plan_version, payload, occurred_at_utc)
  VALUES (
    v_token.organization_id, 'SANCTION_ACKNOWLEDGED', 'PORTAL',
    v_queue.set_id, v_queue.contract_id::uuid, 0,
    jsonb_build_object(
      'queue_entry_id', v_token.queue_entry_id,
      'acknowledgement_id', v_ack,
      'method', 'PORTAL_TOKEN',
      'token_id', v_token.id,
      'snapshot_hash', p_snapshot_hash
    ),
    v_now
  );

  RETURN v_ack;
END;
$$;

REVOKE ALL ON FUNCTION public.acknowledge_via_portal(UUID,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.acknowledge_via_portal(UUID,TEXT)
  TO anon, authenticated;

RESET client_min_messages;
