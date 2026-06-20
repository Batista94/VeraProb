-- =============================================================================
-- Migration: recycle disputes + revoke portal access on internal verdict
-- Purpose:   Complete the dispute-cycle discriminator (20260823000001) and seal
--            the "Revogação de Acesso Externo" requirement.
--
--   (A) dispute_sanction increments sanction_review_queue.dispute_round on each
--       open, so every open→resolve cycle owns a fresh resolution slot.
--   (B) resolve_dispute / confirm_peer_review embed 'dispute_round' in the
--       resolution payload (keys the cycle-scoped unique index).
--   (C) Every internal verdict that leaves the 'disputed' lifecycle revokes the
--       outstanding portal token in the SAME transaction (revoked_at_utc +
--       revoked_reason = 'VERDICT_SEALED') — phantom attachments are blocked the
--       instant the sanction is judged internally. read_dispute_portal then
--       surfaces "SLA encerrado" (20260823000003).
--
-- Each RPC is CREATE OR REPLACE-based on its LATEST definition:
--   dispute_sanction      → 20260813000010
--   resolve_dispute (9p)  → 20260813000008
--   reject_sanction (7p)  → 20260813000008
--   confirm_peer_review   → 20260813000008
--   approve_sanction (7p) → 20260819000001
-- Signatures are UNCHANGED (no DROP) — committed pgTAP keeps passing.
--
-- pr_scanner: ignore-regression — additive RPC refactor (CREATE OR REPLACE on
--   existing signatures; additive column). No merged migration file modified.
--   Dual-control fork preserved verbatim. Council-approved.
-- Invariants: INV-1, INV-3, INV-6, INV-10, INV-15, INV-22, INV-23, INV-26.
-- =============================================================================

SET client_min_messages TO 'WARNING';

-- ── 0. Forensic provenance: why a portal token was revoked ───────────────────
-- Nullable, set once at revocation time. Not in prevent_dpt_immutable_mutation()
-- blocklist; the single-revoke guard (WHERE revoked_at_utc IS NULL) keeps it
-- write-once in practice. Distinguishes seal-revocation from admin revocation.
ALTER TABLE public.dispute_portal_tokens
  ADD COLUMN IF NOT EXISTS revoked_reason TEXT;

COMMENT ON COLUMN public.dispute_portal_tokens.revoked_reason IS
  'Why the token was revoked. VERDICT_SEALED = sanction judged internally '
  '(external defense window closed in the same txn as the verdict).';

-- ── 1. dispute_sanction — increment dispute_round on open ────────────────────
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
  v_next_round INT;
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

  -- ── New dispute cycle: recycle the resolution slot (20260823000001) ─────────
  v_next_round := COALESCE(v_queue.dispute_round, 0) + 1;

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
      'dispute_sla_days', v_sla_days,
      'dispute_round', v_next_round
    ),
    p_occurred_at_utc
  )
  RETURNING id INTO v_ledger_id;

  -- ── Flip queue status + seal dispute provenance (INV-23) + bump round ───────
  UPDATE public.sanction_review_queue
     SET status = 'disputed',
         reviewed_at = p_occurred_at_utc,
         reviewed_by = v_user,
         disputed_at = p_occurred_at_utc,          -- sealed (INV-23: NEVER cleared)
         disputed_by = v_user,                     -- sealed (INV-23: NEVER cleared)
         resolution_due_at = v_resolution_due,      -- SLA timer (Q3)
         dispute_round = v_next_round                -- recycle resolution slot
   WHERE id = p_queue_entry_id AND organization_id = p_organization_id;

  RETURN jsonb_build_object(
    'ledger_entry_id', v_ledger_id,
    'status', 'disputed',
    'resolution_due_at', v_resolution_due,
    'dispute_round', v_next_round
  );
END;
$$;

-- ── 2. resolve_dispute (9-param) — embed dispute_round + revoke token ─────────
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

  -- Taxonomy validation (Q2). Same 42501 / generic message as wrong-org (H5/INV-26).
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

  -- B2: a verdict can NEVER seal over tampered (MISMATCH) evidence.
  IF p_resolution IN ('DISPUTE_ACCEPTED', 'DISPUTE_OVERTURNED') THEN
    SELECT count(*) INTO v_mismatch FROM public.dispute_evidence_attachments
      WHERE queue_entry_id = p_queue_entry_id AND organization_id = p_organization_id
        AND deleted_at IS NULL AND verification_status = 'MISMATCH';
    IF v_mismatch > 0 THEN
      RAISE EXCEPTION 'Dispute resolution rejected.' USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  -- Collect verified evidence (only non-deleted) for embedding.
  SELECT COALESCE(jsonb_agg(id ORDER BY attached_at), '[]'::jsonb),
         COALESCE(jsonb_agg(sha256_hash ORDER BY attached_at), '[]'::jsonb)
    INTO v_evidence_ids, v_evidence_hashes
    FROM public.dispute_evidence_attachments
   WHERE queue_entry_id = p_queue_entry_id AND organization_id = p_organization_id
     AND deleted_at IS NULL;

  -- ── Dual-control fork: enforce/waive only (PRESERVED verbatim from 10.5) ────
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

  -- ── Terminal path ───────────────────────────────────────────────────────────
  INSERT INTO public.sla_audit_ledger_v2
    (organization_id, type, operator_id, set_id, contract_id, plan_version, payload, occurred_at_utc)
  VALUES (
    p_organization_id, p_resolution, p_resolved_by_user_id::text, v_queue.set_id,
    v_queue.contract_id::uuid, 0,
    jsonb_build_object(
      'queue_entry_id', p_queue_entry_id,
      'dispute_round', v_queue.dispute_round,   -- cycle discriminator (20260823000001)
      'resolved_by_user_id', p_resolved_by_user_id,
      'actor_email', p_actor_email,
      'resolution_reason', NULLIF(btrim(p_resolution_reason), ''),
      'reason_code', p_reason_code,
      'evidence_attachment_ids', v_evidence_ids,
      'evidence_hashes', v_evidence_hashes,
      -- INV-23: on retract, preserve who opened.
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
           WHEN p_resolution = 'DISPUTE_ACCEPTED'  THEN NULLIF(btrim(p_resolution_reason), '')
           WHEN p_resolution = 'DISPUTE_RETRACTED' THEN NULL
           ELSE rejection_reason END,
         resolution_reason_code = CASE
           WHEN p_resolution IN ('DISPUTE_ACCEPTED','DISPUTE_OVERTURNED') THEN p_reason_code
           ELSE resolution_reason_code END,
         rejection_reason_code = CASE
           WHEN p_resolution = 'DISPUTE_ACCEPTED' THEN p_reason_code
           ELSE rejection_reason_code END
         -- disputed_by / disputed_at NEVER cleared (INV-23).
   WHERE id = p_queue_entry_id AND organization_id = p_organization_id;

  -- ── Revoke external portal access — dispute cycle closed (Revogação) ─────────
  -- Every arc out of 'disputed' (accept/overturn/retract) ends this round's
  -- defense window. The outstanding token (≤1 active per entry) is revoked in the
  -- same txn so no phantom attachment can land after the verdict. A fresh dispute
  -- issues a fresh token.
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

  RETURN jsonb_build_object('ledger_entry_id', v_ledger_id, 'status', v_new_status, 'snapshot', v_snapshot);
END;
$$;

-- ── 3. reject_sanction (7-param) — revoke token on terminal (defense-in-depth) ─
CREATE OR REPLACE FUNCTION public.reject_sanction(
  p_organization_id     UUID,
  p_queue_entry_id      UUID,
  p_reviewed_by_user_id UUID,
  p_actor_email         TEXT,
  p_rejection_reason    TEXT,
  p_reason_code         TEXT,
  p_occurred_at_utc     TIMESTAMPTZ
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  v_jwt_org TEXT; v_jwt_role TEXT; v_user UUID; v_reason TEXT;
  v_queue public.sanction_review_queue; v_ledger_id UUID;
  v_fine BIGINT; v_threshold BIGINT; v_ttl INT;
BEGIN
  v_jwt_org := auth.jwt() -> 'app_metadata' ->> 'org_id';
  IF v_jwt_org IS NULL OR v_jwt_org::uuid <> p_organization_id THEN
    RAISE EXCEPTION 'Sanction rejection rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  v_jwt_role := auth.jwt() -> 'app_metadata' ->> 'role';
  IF v_jwt_role IS NULL OR v_jwt_role NOT IN ('TENANT_ADMIN', 'AUDITOR') THEN
    RAISE EXCEPTION 'Sanction rejection rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  v_reason := NULLIF(btrim(p_rejection_reason), '');
  -- reason_code now mandatory (Q2); free text optional complement.
  IF p_reason_code IS NULL OR btrim(p_reason_code) = '' THEN
    RAISE EXCEPTION 'Sanction rejection rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.dispute_reason_codes
                  WHERE code = p_reason_code AND is_active = TRUE AND organization_id IS NULL) THEN
    RAISE EXCEPTION 'Sanction rejection rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  v_user := (auth.jwt() ->> 'sub')::uuid;
  IF v_user IS NULL OR v_user <> p_reviewed_by_user_id THEN
    RAISE EXCEPTION 'Sanction rejection rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_queue FROM public.sanction_review_queue
   WHERE id = p_queue_entry_id AND organization_id = p_organization_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Sanction rejection rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF v_queue.status <> 'pending' THEN
    RAISE EXCEPTION 'This sanction has already been reviewed by another auditor.'
      USING ERRCODE = 'P0001', DETAIL = 'IdempotencyProcessingException';
  END IF;

  v_fine := (v_queue.verdict_evidence ->> 'fine_cents')::bigint;
  v_threshold := public._resolve_dual_control_threshold(p_organization_id, v_queue.contract_id);
  v_ttl := public._resolve_dual_control_ttl(p_organization_id);

  IF v_threshold IS NOT NULL AND v_fine > v_threshold THEN
    UPDATE public.sanction_review_queue
       SET status = 'pending_peer_review',
           first_reviewer_id = v_user,
           first_reviewed_at = p_occurred_at_utc,
           peer_review_origin_status = 'pending',
           peer_review_proposed_action = 'REJECT',
           peer_review_reason = v_reason,
           peer_review_reason_code = p_reason_code,
           peer_review_expires_at = p_occurred_at_utc + make_interval(hours => v_ttl)
     WHERE id = p_queue_entry_id AND organization_id = p_organization_id;
    v_ledger_id := public._append_peer_review_requested(
      p_organization_id, v_queue, v_user, p_actor_email, 'REJECT',
      v_reason, v_fine, v_threshold, p_occurred_at_utc);
    RETURN jsonb_build_object('ledger_entry_id', v_ledger_id, 'status', 'pending_peer_review');
  END IF;

  INSERT INTO public.sla_audit_ledger_v2
    (organization_id, type, operator_id, set_id, contract_id, plan_version, payload, occurred_at_utc)
  VALUES (
    p_organization_id, 'VERDICT_REFUSED', v_user::text, v_queue.set_id,
    v_queue.contract_id::uuid, 0,
    jsonb_build_object(
      'queue_entry_id', p_queue_entry_id, 'rejected_by_user_id', v_user,
      'actor_email', p_actor_email, 'rejection_reason', v_reason,
      'reason_code', p_reason_code, 'verdict_evidence', v_queue.verdict_evidence),
    p_occurred_at_utc)
  RETURNING id INTO v_ledger_id;

  UPDATE public.sanction_review_queue
     SET status = 'rejected', reviewed_at = p_occurred_at_utc, reviewed_by = v_user,
         rejection_reason = v_reason, rejection_reason_code = p_reason_code
   WHERE id = p_queue_entry_id AND organization_id = p_organization_id;

  -- Defense-in-depth: a 'pending' sanction normally has no portal token, but if
  -- one was issued, revoke it on the terminal refusal.
  UPDATE public.dispute_portal_tokens
     SET revoked_at_utc = p_occurred_at_utc, revoked_reason = 'VERDICT_SEALED'
   WHERE organization_id = p_organization_id
     AND queue_entry_id  = p_queue_entry_id
     AND revoked_at_utc IS NULL;

  RETURN jsonb_build_object('ledger_entry_id', v_ledger_id, 'status', 'rejected');
END;
$$;

-- ── 4. confirm_peer_review — embed dispute_round + revoke token on terminal ───
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

  -- ★ ANTI-FRAUD: reviewer2 != reviewer1 (both from JWT sub).
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
      'dispute_round', v_queue.dispute_round,   -- cycle discriminator (only meaningful for DISPUTE_* types)
      'first_reviewer_id', v_queue.first_reviewer_id,
      'second_reviewer_id', v_user, 'confirmed_by_user_id', v_user,
      'actor_email', p_actor_email,
      'proposed_action', v_queue.peer_review_proposed_action,
      'rejection_reason', v_queue.peer_review_reason,
      'reason_code', v_queue.peer_review_reason_code,   -- threaded (Senior F5)
      'verdict_evidence', v_queue.verdict_evidence),
    p_occurred_at_utc)
  RETURNING id INTO v_ledger_id;

  UPDATE public.sanction_review_queue
     SET status = v_final_status, reviewed_at = p_occurred_at_utc, reviewed_by = v_user,
         rejection_reason = CASE WHEN v_final_status = 'rejected' THEN v_queue.peer_review_reason ELSE rejection_reason END,
         rejection_reason_code = CASE
           WHEN v_queue.peer_review_proposed_action IN ('REJECT','DISPUTE_ACCEPT') THEN v_queue.peer_review_reason_code
           ELSE rejection_reason_code END,
         resolution_reason_code = CASE
           WHEN v_queue.peer_review_proposed_action IN ('OVERTURN','DISPUTE_ACCEPT') THEN v_queue.peer_review_reason_code
           ELSE resolution_reason_code END,
         first_reviewer_id = NULL, first_reviewed_at = NULL,
         peer_review_origin_status = NULL, peer_review_proposed_action = NULL,
         peer_review_reason = NULL, peer_review_reason_code = NULL, peer_review_expires_at = NULL
   WHERE id = p_queue_entry_id AND organization_id = p_organization_id;

  -- ── Revoke external portal access — verdict sealed by second auditor ─────────
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

  RETURN jsonb_build_object('ledger_entry_id', v_ledger_id, 'status', v_final_status, 'snapshot', v_snapshot);
END;
$$;

-- ── 5. approve_sanction (7-param) — revoke token on terminal (defense-in-depth) ─
CREATE OR REPLACE FUNCTION public.approve_sanction(
  p_organization_id     UUID,
  p_queue_entry_id      UUID,
  p_reviewed_by_user_id UUID,
  p_actor_email         TEXT,
  p_occurred_at_utc     TIMESTAMPTZ,
  p_reason_code         TEXT DEFAULT NULL,
  p_reviewer_reason     TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_jwt_org         TEXT;
  v_jwt_role        TEXT;
  v_user            UUID;
  v_queue           public.sanction_review_queue;
  v_ledger_id       UUID;
  v_fine            BIGINT;
  v_threshold       BIGINT;
  v_ttl             INT;
  v_reason_code     TEXT;
  v_reviewer_reason TEXT;
BEGIN
  v_jwt_org := auth.jwt() -> 'app_metadata' ->> 'org_id';
  IF v_jwt_org IS NULL OR v_jwt_org::uuid <> p_organization_id THEN
    RAISE EXCEPTION 'Sanction approval rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  v_jwt_role := auth.jwt() -> 'app_metadata' ->> 'role';
  IF v_jwt_role IS NULL OR v_jwt_role NOT IN ('TENANT_ADMIN', 'AUDITOR') THEN
    RAISE EXCEPTION 'Sanction approval rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  v_reason_code := NULLIF(btrim(p_reason_code), '');
  IF v_reason_code IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM public.dispute_reason_codes
                      WHERE code = v_reason_code
                        AND is_active = TRUE
                        AND organization_id IS NULL) THEN
    RAISE EXCEPTION 'Sanction approval rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  v_reviewer_reason := NULLIF(btrim(p_reviewer_reason), '');

  v_user := (auth.jwt() ->> 'sub')::uuid;
  IF v_user IS NULL OR v_user <> p_reviewed_by_user_id THEN
    RAISE EXCEPTION 'Sanction approval rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_queue
    FROM public.sanction_review_queue
   WHERE id = p_queue_entry_id AND organization_id = p_organization_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Sanction approval rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_queue.status <> 'pending' THEN
    RAISE EXCEPTION 'This sanction has already been reviewed by another auditor.'
      USING ERRCODE = 'P0001', DETAIL = 'IdempotencyProcessingException';
  END IF;

  v_fine := (v_queue.verdict_evidence ->> 'fine_cents')::bigint;
  v_threshold := public._resolve_dual_control_threshold(p_organization_id, v_queue.contract_id);
  v_ttl := public._resolve_dual_control_ttl(p_organization_id);

  IF v_threshold IS NOT NULL AND v_fine > v_threshold THEN
    UPDATE public.sanction_review_queue
       SET status = 'pending_peer_review',
           first_reviewer_id = v_user,
           first_reviewed_at = p_occurred_at_utc,
           peer_review_origin_status = 'pending',
           peer_review_proposed_action = 'APPROVE',
           peer_review_reason = NULL,
           peer_review_expires_at = p_occurred_at_utc + make_interval(hours => v_ttl)
     WHERE id = p_queue_entry_id AND organization_id = p_organization_id;

    v_ledger_id := public._append_peer_review_requested(
      p_organization_id, v_queue, v_user, p_actor_email, 'APPROVE',
      NULL, v_fine, v_threshold, p_occurred_at_utc);

    RETURN jsonb_build_object('ledger_entry_id', v_ledger_id, 'status', 'pending_peer_review');
  END IF;

  -- ── Terminal path: seal verdict ──────────────────────────────────────────────
  INSERT INTO public.sla_audit_ledger_v2
    (organization_id, type, operator_id, set_id, contract_id, plan_version, payload, occurred_at_utc)
  VALUES (
    p_organization_id, 'VERDICT_SEALED', v_user::text, v_queue.set_id,
    v_queue.contract_id::uuid, 0,
    jsonb_build_object(
      'queue_entry_id', p_queue_entry_id,
      'approved_by_user_id', v_user,
      'actor_email', p_actor_email,
      'reason_code', v_reason_code,
      'reviewer_reason', v_reviewer_reason,
      'verdict_evidence', v_queue.verdict_evidence
    ),
    p_occurred_at_utc
  )
  RETURNING id INTO v_ledger_id;

  -- Seal forensic snapshot bound to this queue entry (INV-9, INV-21).
  PERFORM public._persist_evidence_snapshot(
    p_organization_id,
    v_queue.contract_id::uuid,
    v_ledger_id,
    p_queue_entry_id,
    'VERDICT_SEALED',
    v_queue.set_id,
    0,
    p_occurred_at_utc,
    v_user,
    'approve:' || p_queue_entry_id::text
  );

  UPDATE public.sanction_review_queue
     SET status = 'applied', reviewed_at = p_occurred_at_utc, reviewed_by = v_user
   WHERE id = p_queue_entry_id AND organization_id = p_organization_id;

  -- Defense-in-depth: revoke any outstanding portal token on the sealed verdict.
  UPDATE public.dispute_portal_tokens
     SET revoked_at_utc = p_occurred_at_utc, revoked_reason = 'VERDICT_SEALED'
   WHERE organization_id = p_organization_id
     AND queue_entry_id  = p_queue_entry_id
     AND revoked_at_utc IS NULL;

  RETURN jsonb_build_object('ledger_entry_id', v_ledger_id, 'status', 'applied');
END;
$$;

-- ── Re-affirm grants (CREATE OR REPLACE preserves them; explicit for parity) ──
REVOKE ALL ON FUNCTION public.dispute_sanction(UUID, UUID, UUID, TEXT, TIMESTAMPTZ)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.dispute_sanction(UUID, UUID, UUID, TEXT, TIMESTAMPTZ)
  TO authenticated;
REVOKE ALL ON FUNCTION public.resolve_dispute(UUID, UUID, TEXT, TEXT, UUID, TEXT, TIMESTAMPTZ, TEXT, TEXT)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.resolve_dispute(UUID, UUID, TEXT, TEXT, UUID, TEXT, TIMESTAMPTZ, TEXT, TEXT)
  TO authenticated;
REVOKE ALL ON FUNCTION public.reject_sanction(UUID, UUID, UUID, TEXT, TEXT, TEXT, TIMESTAMPTZ)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.reject_sanction(UUID, UUID, UUID, TEXT, TEXT, TEXT, TIMESTAMPTZ)
  TO authenticated;
REVOKE ALL ON FUNCTION public.confirm_peer_review(UUID, UUID, UUID, TEXT, TIMESTAMPTZ, TEXT)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.confirm_peer_review(UUID, UUID, UUID, TEXT, TIMESTAMPTZ, TEXT)
  TO authenticated;
REVOKE ALL ON FUNCTION public.approve_sanction(UUID, UUID, UUID, TEXT, TIMESTAMPTZ, TEXT, TEXT)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.approve_sanction(UUID, UUID, UUID, TEXT, TIMESTAMPTZ, TEXT, TEXT)
  TO authenticated;

RESET client_min_messages;
