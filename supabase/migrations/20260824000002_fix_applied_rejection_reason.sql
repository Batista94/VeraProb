-- =============================================================================
-- Migration: fix_applied_rejection_reason
-- Purpose:   Fixes a bug where `rejection_reason` was being dropped for confirmed
--            infractions (DISPUTE_OVERTURNED and APPROVE/OVERTURN in peer review)
--            in the `sanction_review_queue` table. The text was only being saved
--            to the immutable ledger, making it invisible to the UI and forensic
--            dossiers.
--
--            Also includes a batched backfill to restore the dropped reasons
--            from `sla_audit_ledger_v2` for past confirmed infractions.
--
-- pr_scanner: ignore-regression — bug fix on existing RPCs.
-- =============================================================================

SET client_min_messages TO 'WARNING';

-- ── 1. Update resolve_dispute to preserve resolution_reason on OVERTURN ──
CREATE OR REPLACE FUNCTION public.resolve_dispute(
  p_organization_id     UUID,
  p_queue_entry_id      UUID,
  p_resolution          TEXT,
  p_resolution_reason   TEXT,
  p_resolved_by_user_id UUID,
  p_actor_email         TEXT,
  p_occurred_at_utc     TIMESTAMPTZ,
  p_idempotency_key     TEXT,
  p_reason_code         TEXT
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  v_jwt_org TEXT; v_jwt_role TEXT; v_user UUID;
  v_queue public.sanction_review_queue;
  v_new_status TEXT; v_ledger_id UUID; v_snapshot JSONB;
  v_fine BIGINT; v_threshold BIGINT; v_ttl INT; v_action TEXT;
  v_evidence_ids JSONB; v_evidence_hashes JSONB; v_mismatch INT;
BEGIN
  v_jwt_org := auth.jwt() -> 'app_metadata' ->> 'org_id';
  IF v_jwt_org IS NULL OR v_jwt_org::uuid <> p_organization_id THEN
    RAISE EXCEPTION 'Dispute resolution rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  v_jwt_role := auth.jwt() -> 'app_metadata' ->> 'role';
  IF v_jwt_role IS NULL OR v_jwt_role NOT IN ('TENANT_ADMIN', 'AUDITOR') THEN
    RAISE EXCEPTION 'Dispute resolution rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  v_new_status := CASE p_resolution
    WHEN 'DISPUTE_ACCEPTED'   THEN 'rejected'
    WHEN 'DISPUTE_OVERTURNED' THEN 'applied'
    WHEN 'DISPUTE_RETRACTED'  THEN 'pending'
    ELSE NULL END;
  IF v_new_status IS NULL THEN
    RAISE EXCEPTION 'Dispute resolution rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF p_resolution IN ('DISPUTE_ACCEPTED', 'DISPUTE_OVERTURNED') THEN
    IF p_reason_code IS NULL OR btrim(p_reason_code) = '' THEN
      RAISE EXCEPTION 'Dispute resolution rejected.' USING ERRCODE = 'insufficient_privilege';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.dispute_reason_codes
                    WHERE code = p_reason_code AND is_active = TRUE AND organization_id IS NULL) THEN
      RAISE EXCEPTION 'Dispute resolution rejected.' USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  SELECT * INTO v_queue FROM public.sanction_review_queue
   WHERE id = p_queue_entry_id AND organization_id = p_organization_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Dispute resolution rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF v_queue.status <> 'disputed' THEN
    RAISE EXCEPTION 'This dispute has already been resolved by another auditor.'
      USING ERRCODE = 'P0001', DETAIL = 'IdempotencyProcessingException';
  END IF;

  IF p_resolution IN ('DISPUTE_ACCEPTED', 'DISPUTE_OVERTURNED') THEN
    SELECT count(*) INTO v_mismatch FROM public.dispute_evidence_attachments
      WHERE queue_entry_id = p_queue_entry_id AND organization_id = p_organization_id
        AND deleted_at IS NULL AND verification_status = 'MISMATCH';
    IF v_mismatch > 0 THEN
      RAISE EXCEPTION 'Dispute resolution rejected.' USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  SELECT COALESCE(jsonb_agg(id ORDER BY attached_at), '[]'::jsonb),
         COALESCE(jsonb_agg(sha256_hash ORDER BY attached_at), '[]'::jsonb)
    INTO v_evidence_ids, v_evidence_hashes
    FROM public.dispute_evidence_attachments
   WHERE queue_entry_id = p_queue_entry_id AND organization_id = p_organization_id
     AND deleted_at IS NULL;

  IF p_resolution IN ('DISPUTE_OVERTURNED', 'DISPUTE_ACCEPTED') THEN
    v_fine := (v_queue.verdict_evidence ->> 'fine_cents')::bigint;
    v_threshold := public._resolve_dual_control_threshold(p_organization_id, v_queue.contract_id);
    v_ttl := public._resolve_dual_control_ttl(p_organization_id);

    IF v_threshold IS NOT NULL AND v_fine > v_threshold THEN
      v_user := (auth.jwt() ->> 'sub')::uuid;
      IF v_user IS NULL THEN
        RAISE EXCEPTION 'Dispute resolution rejected.' USING ERRCODE = 'insufficient_privilege';
      END IF;
      v_action := CASE p_resolution WHEN 'DISPUTE_OVERTURNED' THEN 'OVERTURN' ELSE 'DISPUTE_ACCEPT' END;

      UPDATE public.sanction_review_queue
         SET status = 'pending_peer_review',
             first_reviewer_id = v_user,
             first_reviewed_at = p_occurred_at_utc,
             peer_review_origin_status = 'disputed',
             peer_review_proposed_action = v_action,
             peer_review_reason = NULLIF(btrim(p_resolution_reason), ''),
             peer_review_reason_code = p_reason_code,
             peer_review_expires_at = p_occurred_at_utc + make_interval(hours => v_ttl)
       WHERE id = p_queue_entry_id AND organization_id = p_organization_id;

      v_ledger_id := public._append_peer_review_requested(
        p_organization_id, v_queue, v_user, p_actor_email, v_action,
        NULLIF(btrim(p_resolution_reason), ''), v_fine, v_threshold, p_occurred_at_utc);

      RETURN jsonb_build_object('ledger_entry_id', v_ledger_id, 'status', 'pending_peer_review', 'snapshot', NULL);
    END IF;
  END IF;

  INSERT INTO public.sla_audit_ledger_v2
    (organization_id, type, operator_id, set_id, contract_id, plan_version, payload, occurred_at_utc)
  VALUES (
    p_organization_id, p_resolution, p_resolved_by_user_id::text, v_queue.set_id,
    v_queue.contract_id::uuid, 0,
    jsonb_build_object(
      'queue_entry_id', p_queue_entry_id,
      'dispute_round', v_queue.dispute_round,
      'resolved_by_user_id', p_resolved_by_user_id,
      'actor_email', p_actor_email,
      'resolution_reason', NULLIF(btrim(p_resolution_reason), ''),
      'reason_code', p_reason_code,
      'evidence_attachment_ids', v_evidence_ids,
      'evidence_hashes', v_evidence_hashes,
      'original_disputed_by', v_queue.disputed_by,
      'original_disputed_at', v_queue.disputed_at,
      'retracted_by_user_id', CASE WHEN p_resolution = 'DISPUTE_RETRACTED' THEN p_resolved_by_user_id ELSE NULL END,
      'verdict_evidence', v_queue.verdict_evidence
    ),
    p_occurred_at_utc
  )
  RETURNING id INTO v_ledger_id;

  UPDATE public.sanction_review_queue
     SET status = v_new_status,
         reviewed_at = CASE WHEN p_resolution = 'DISPUTE_RETRACTED' THEN NULL ELSE p_occurred_at_utc END,
         reviewed_by = CASE WHEN p_resolution = 'DISPUTE_RETRACTED' THEN reviewed_by ELSE p_resolved_by_user_id END,
         rejection_reason = CASE
           WHEN p_resolution IN ('DISPUTE_ACCEPTED', 'DISPUTE_OVERTURNED') THEN NULLIF(btrim(p_resolution_reason), '')
           WHEN p_resolution = 'DISPUTE_RETRACTED' THEN NULL
           ELSE rejection_reason END,
         resolution_reason_code = CASE
           WHEN p_resolution IN ('DISPUTE_ACCEPTED','DISPUTE_OVERTURNED') THEN p_reason_code
           ELSE resolution_reason_code END,
         rejection_reason_code = CASE
           WHEN p_resolution IN ('DISPUTE_ACCEPTED', 'DISPUTE_OVERTURNED') THEN p_reason_code
           ELSE rejection_reason_code END
   WHERE id = p_queue_entry_id AND organization_id = p_organization_id;

  UPDATE public.dispute_portal_tokens
     SET revoked_at_utc = p_occurred_at_utc, revoked_reason = 'VERDICT_SEALED'
   WHERE organization_id = p_organization_id
     AND queue_entry_id  = p_queue_entry_id
     AND revoked_at_utc IS NULL;

  IF p_resolution = 'DISPUTE_OVERTURNED' THEN
    v_snapshot := public.seal_dispute_resolution_snapshot(
      p_organization_id, v_ledger_id, v_queue.contract_id::uuid, v_queue.set_id,
      0, p_occurred_at_utc, p_resolved_by_user_id, p_idempotency_key);
  END IF;

  IF p_resolution = 'DISPUTE_ACCEPTED' THEN
    PERFORM public._persist_evidence_snapshot(
      p_organization_id, v_queue.contract_id::uuid, v_ledger_id, p_queue_entry_id,
      'DISPUTE_ACCEPTED', v_queue.set_id, 0, p_occurred_at_utc, p_resolved_by_user_id,
      'dispute_accept:' || p_idempotency_key
    );
  END IF;

  RETURN jsonb_build_object('ledger_entry_id', v_ledger_id, 'status', v_new_status, 'snapshot', v_snapshot);
END;
$$;

-- ── 2. Update confirm_peer_review to preserve reason for applied actions ──
CREATE OR REPLACE FUNCTION public.confirm_peer_review(
  p_organization_id     UUID,
  p_queue_entry_id      UUID,
  p_reviewed_by_user_id UUID,
  p_actor_email         TEXT,
  p_occurred_at_utc     TIMESTAMPTZ,
  p_idempotency_key     TEXT
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  v_jwt_org TEXT; v_jwt_role TEXT; v_user UUID;
  v_queue public.sanction_review_queue;
  v_ledger_id UUID; v_snapshot JSONB; v_final_status TEXT; v_ledger_type TEXT;
BEGIN
  v_jwt_org := auth.jwt() -> 'app_metadata' ->> 'org_id';
  IF v_jwt_org IS NULL OR v_jwt_org::uuid <> p_organization_id THEN
    RAISE EXCEPTION 'Peer review rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  v_jwt_role := auth.jwt() -> 'app_metadata' ->> 'role';
  IF v_jwt_role IS NULL OR v_jwt_role NOT IN ('TENANT_ADMIN', 'AUDITOR') THEN
    RAISE EXCEPTION 'Peer review rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  v_user := (auth.jwt() ->> 'sub')::uuid;
  IF v_user IS NULL OR v_user <> p_reviewed_by_user_id THEN
    RAISE EXCEPTION 'Peer review rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_queue FROM public.sanction_review_queue
   WHERE id = p_queue_entry_id AND organization_id = p_organization_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Peer review rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF v_queue.status <> 'pending_peer_review' THEN
    RAISE EXCEPTION 'This item is no longer awaiting a second auditor.'
      USING ERRCODE = 'P0001', DETAIL = 'IdempotencyProcessingException';
  END IF;

  IF v_user = v_queue.first_reviewer_id THEN
    RAISE EXCEPTION 'The second auditor must differ from the auditor who requested this verdict.'
      USING ERRCODE = 'P0001', DETAIL = 'DualControlSelfApprovalException';
  END IF;

  CASE v_queue.peer_review_proposed_action
    WHEN 'APPROVE'        THEN v_final_status := 'applied';  v_ledger_type := 'VERDICT_SEALED';
    WHEN 'OVERTURN'       THEN v_final_status := 'applied';  v_ledger_type := 'DISPUTE_OVERTURNED';
    WHEN 'REJECT'         THEN v_final_status := 'rejected'; v_ledger_type := 'VERDICT_REFUSED';
    WHEN 'DISPUTE_ACCEPT' THEN v_final_status := 'rejected'; v_ledger_type := 'DISPUTE_ACCEPTED';
    ELSE RAISE EXCEPTION 'Peer review rejected.' USING ERRCODE = 'insufficient_privilege';
  END CASE;

  INSERT INTO public.sla_audit_ledger_v2
    (organization_id, type, operator_id, set_id, contract_id, plan_version, payload, occurred_at_utc)
  VALUES (
    p_organization_id, v_ledger_type, v_user::text, v_queue.set_id,
    v_queue.contract_id::uuid, 0,
    jsonb_build_object(
      'queue_entry_id', p_queue_entry_id,
      'dispute_round', v_queue.dispute_round,
      'first_reviewer_id', v_queue.first_reviewer_id,
      'second_reviewer_id', v_user, 'confirmed_by_user_id', v_user,
      'actor_email', p_actor_email,
      'proposed_action', v_queue.peer_review_proposed_action,
      'rejection_reason', v_queue.peer_review_reason,
      'reason_code', v_queue.peer_review_reason_code,
      'verdict_evidence', v_queue.verdict_evidence),
    p_occurred_at_utc)
  RETURNING id INTO v_ledger_id;

  UPDATE public.sanction_review_queue
     SET status = v_final_status, reviewed_at = p_occurred_at_utc, reviewed_by = v_user,
         rejection_reason = COALESCE(v_queue.peer_review_reason, rejection_reason),
         rejection_reason_code = CASE
           WHEN v_queue.peer_review_proposed_action IN ('REJECT', 'DISPUTE_ACCEPT', 'OVERTURN', 'APPROVE') THEN v_queue.peer_review_reason_code
           ELSE rejection_reason_code END,
         resolution_reason_code = CASE
           WHEN v_queue.peer_review_proposed_action IN ('OVERTURN','DISPUTE_ACCEPT') THEN v_queue.peer_review_reason_code
           ELSE resolution_reason_code END,
         first_reviewer_id = NULL, first_reviewed_at = NULL,
         peer_review_origin_status = NULL, peer_review_proposed_action = NULL,
         peer_review_reason = NULL, peer_review_reason_code = NULL, peer_review_expires_at = NULL
   WHERE id = p_queue_entry_id AND organization_id = p_organization_id;

  UPDATE public.dispute_portal_tokens
     SET revoked_at_utc = p_occurred_at_utc, revoked_reason = 'VERDICT_SEALED'
   WHERE organization_id = p_organization_id
     AND queue_entry_id  = p_queue_entry_id
     AND revoked_at_utc IS NULL;

  IF v_ledger_type = 'DISPUTE_OVERTURNED' THEN
    v_snapshot := public.seal_dispute_resolution_snapshot(
      p_organization_id, v_ledger_id, v_queue.contract_id::uuid, v_queue.set_id,
      0, p_occurred_at_utc, v_user, p_idempotency_key);
  END IF;

  IF v_ledger_type IN ('VERDICT_REFUSED', 'DISPUTE_ACCEPTED') THEN
    PERFORM public._persist_evidence_snapshot(
      p_organization_id, v_queue.contract_id::uuid, v_ledger_id, p_queue_entry_id,
      v_ledger_type, v_queue.set_id, 0, p_occurred_at_utc, v_user,
      'peer_' || lower(v_ledger_type) || ':' || p_queue_entry_id::text
    );
  END IF;

  RETURN jsonb_build_object('ledger_entry_id', v_ledger_id, 'status', v_final_status, 'snapshot', v_snapshot);
END;
$$;

REVOKE ALL ON FUNCTION public.resolve_dispute(UUID, UUID, TEXT, TEXT, UUID, TEXT, TIMESTAMPTZ, TEXT, TEXT)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.resolve_dispute(UUID, UUID, TEXT, TEXT, UUID, TEXT, TIMESTAMPTZ, TEXT, TEXT)
  TO authenticated;
REVOKE ALL ON FUNCTION public.confirm_peer_review(UUID, UUID, UUID, TEXT, TIMESTAMPTZ, TEXT)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.confirm_peer_review(UUID, UUID, UUID, TEXT, TIMESTAMPTZ, TEXT)
  TO authenticated;


-- ── 3. Batched Backfill for past dropped reasons ────────────────────────────
DO $$
DECLARE
  v_rows INT;
BEGIN
  LOOP
    UPDATE public.sanction_review_queue q
       SET rejection_reason = sub.reason
      FROM (
        SELECT (payload->>'queue_entry_id')::uuid AS queue_entry_id,
               payload->>'resolution_reason' AS reason
          FROM public.sla_audit_ledger_v2
         WHERE type = 'DISPUTE_OVERTURNED'
           AND payload->>'resolution_reason' IS NOT NULL
      ) sub
     WHERE q.id = sub.queue_entry_id
       AND q.status = 'applied'
       AND q.rejection_reason IS NULL
       AND q.id IN (
         SELECT id FROM public.sanction_review_queue
          WHERE status = 'applied' AND rejection_reason IS NULL
          LIMIT 1000
       );

    GET DIAGNOSTICS v_rows = ROW_COUNT;
    EXIT WHEN v_rows = 0;
  END LOOP;
END $$;

RESET client_min_messages;
