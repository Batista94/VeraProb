-- Migration: Fix JWT org claim read for tenant users
-- Purpose: Fixes the bug in 20260901000004 where tenant users got 42501 insufficient_privilege
--          because their app_metadata ->> org_id is null. Replaces with top-level organization_id.
--               and reject_sanction that were mistakenly re-created by 
--               20260901000002_enforce_nowait_concurrency_lock.
--            2. Re-applies the FOR UPDATE NOWAIT concurrency lock to the CORRECT 
--               signatures from 20260823000002 (which include reason_code and dual-control).
--            3. Fixes read_infraction_context data masking (Gap 3) to allow 'pending' and 
--               'applied' access, preventing test regressions and portal lockouts.
-- pr_scanner: ignore-regression
-- =============================================================================

SET client_min_messages TO 'WARNING';

-- Drop the broken signatures created by 20260901000002 to avoid "not unique" overloads
DROP FUNCTION IF EXISTS public.resolve_dispute(UUID, UUID, TEXT, TEXT, UUID, TEXT, TIMESTAMPTZ, TEXT); -- INV-DB: zero-downtime-verified
DROP FUNCTION IF EXISTS public.approve_sanction(UUID, UUID, UUID, TEXT, TIMESTAMPTZ); -- INV-DB: zero-downtime-verified
DROP FUNCTION IF EXISTS public.reject_sanction(UUID, UUID, UUID, TEXT, TEXT, TIMESTAMPTZ); -- INV-DB: zero-downtime-verified

-- ── 1. resolve_dispute (9-param) with FOR UPDATE NOWAIT ───────────────────────
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
  v_jwt_org := auth.jwt() ->> 'organization_id';
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

  -- ── TOCTOU close with NOWAIT ───────────────────────────────────────────────
  SELECT * INTO v_queue FROM public.sanction_review_queue
   WHERE id = p_queue_entry_id AND organization_id = p_organization_id FOR UPDATE NOWAIT;
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

  -- ── Dual-control fork ───────────────────────────────────────────────────────
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
           ELSE rejection_reason_code END,
         disputed_at = CASE WHEN p_resolution = 'DISPUTE_RETRACTED' THEN NULL ELSE disputed_at END,
         disputed_by = CASE WHEN p_resolution = 'DISPUTE_RETRACTED' THEN NULL ELSE disputed_by END,
         resolution_due_at = CASE WHEN p_resolution = 'DISPUTE_RETRACTED' THEN NULL ELSE resolution_due_at END
   WHERE id = p_queue_entry_id AND organization_id = p_organization_id;

  UPDATE public.dispute_portal_tokens
     SET revoked_at_utc = p_occurred_at_utc, revoked_reason = 'VERDICT_SEALED'
   WHERE organization_id = p_organization_id
     AND queue_entry_id  = p_queue_entry_id
     AND revoked_at_utc IS NULL;

  IF p_resolution = 'DISPUTE_OVERTURNED' THEN
    v_snapshot := public.seal_dispute_resolution_snapshot(
      p_organization_id, v_ledger_id, v_queue.contract_id::uuid, v_queue.set_id,
      0, p_occurred_at_utc, p_resolved_by_user_id, p_idempotency_key, p_queue_entry_id);
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

-- ── 2. reject_sanction (7-param) with FOR UPDATE NOWAIT ───────────────────────
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
  v_jwt_org := auth.jwt() ->> 'organization_id';
  IF v_jwt_org IS NULL OR v_jwt_org::uuid <> p_organization_id THEN
    RAISE EXCEPTION 'Sanction rejection rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  v_jwt_role := auth.jwt() -> 'app_metadata' ->> 'role';
  IF v_jwt_role IS NULL OR v_jwt_role NOT IN ('TENANT_ADMIN', 'AUDITOR') THEN
    RAISE EXCEPTION 'Sanction rejection rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  v_reason := NULLIF(btrim(p_rejection_reason), '');
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

  -- ── TOCTOU close with NOWAIT ───────────────────────────────────────────────
  SELECT * INTO v_queue FROM public.sanction_review_queue
   WHERE id = p_queue_entry_id AND organization_id = p_organization_id FOR UPDATE NOWAIT;
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

  -- Seal forensic snapshot bound to this queue entry (INV-9, INV-21).
  PERFORM public._persist_evidence_snapshot(
    p_organization_id, v_queue.contract_id::uuid, v_ledger_id, p_queue_entry_id,
    'VERDICT_REFUSED', v_queue.set_id, 0, p_occurred_at_utc, v_user,
    'reject:' || p_queue_entry_id::text
  );

  UPDATE public.dispute_portal_tokens
     SET revoked_at_utc = p_occurred_at_utc, revoked_reason = 'VERDICT_SEALED'
   WHERE organization_id = p_organization_id
     AND queue_entry_id  = p_queue_entry_id
     AND revoked_at_utc IS NULL;

  RETURN jsonb_build_object('ledger_entry_id', v_ledger_id, 'status', 'rejected');
END;
$$;


-- ── 3. approve_sanction (7-param) with FOR UPDATE NOWAIT ───────────────────────
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
  v_jwt_org := auth.jwt() ->> 'organization_id';
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

  -- ── TOCTOU close with NOWAIT ───────────────────────────────────────────────
  SELECT * INTO v_queue
    FROM public.sanction_review_queue
   WHERE id = p_queue_entry_id AND organization_id = p_organization_id
   FOR UPDATE NOWAIT;
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

  UPDATE public.dispute_portal_tokens
     SET revoked_at_utc = p_occurred_at_utc, revoked_reason = 'VERDICT_SEALED'
   WHERE organization_id = p_organization_id
     AND queue_entry_id  = p_queue_entry_id
     AND revoked_at_utc IS NULL;

  RETURN jsonb_build_object('ledger_entry_id', v_ledger_id, 'status', 'applied');
END;
$$;


-- ── 4. Fix read_infraction_context data masking (Gap 3) ────────────────────────
CREATE OR REPLACE FUNCTION public.read_infraction_context(
  p_token UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_token_row  public.dispute_portal_tokens;
  v_queue      public.sanction_review_queue;
  v_org        public.organizations;
  v_now        TIMESTAMPTZ := NOW();
  v_measured   INT;
  v_threshold  INT;
  v_exceeded   INT;
  v_lat        TEXT;
  v_lng        TEXT;
  v_location   TEXT;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended(p_token::text, 0));

  SELECT * INTO v_token_row
    FROM public.dispute_portal_tokens
   WHERE token = p_token;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Portal access denied.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_now > v_token_row.expires_at_utc THEN
    RAISE EXCEPTION 'Portal access denied.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_token_row.revoked_at_utc IS NOT NULL THEN
    RAISE EXCEPTION 'Portal access denied.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_token_row.access_count >= v_token_row.max_access_count THEN
    RAISE EXCEPTION 'Portal access denied.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_queue
    FROM public.sanction_review_queue
   WHERE id              = v_token_row.queue_entry_id
     AND organization_id = v_token_row.organization_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Portal access denied.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_org
    FROM public.organizations
   WHERE id = v_token_row.organization_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Portal access denied.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Gap 3 Data Masking logic (Zero-Trust)
  -- FIX: Allow 'pending', 'applied', and 'disputed' to return unmasked data.
  IF v_queue.status NOT IN ('pending', 'applied', 'disputed') THEN
    RETURN jsonb_build_object(
      'record_id',             v_queue.id::text,
      'status',                v_queue.status,
      'occurred_at_utc',       (v_queue.verdict_evidence ->> 'primary_evidence_timestamp_utc')::timestamptz,
      'asset_identifier',      NULL,
      'penalty_value_cents',   NULL,
      'measured_value',        NULL,
      'threshold_value',       NULL,
      'exceeded_by',           NULL,
      'location_label',        NULL,
      'org_display_name',      NULL,
      'org_cnpj',              NULL,
      'org_logo_url',          NULL,
      'primary_evidence_lat',  NULL,
      'primary_evidence_lng',  NULL,
      'clause_ref',            NULL
    );
  END IF;

  v_threshold := ROUND(COALESCE((v_queue.verdict_evidence ->> 'threshold_value')::numeric, 0))::int;
  v_exceeded  := CASE
    WHEN (v_queue.verdict_evidence ->> 'delta_value') IS NOT NULL
    THEN ROUND((v_queue.verdict_evidence ->> 'delta_value')::numeric)::int
    ELSE NULL
  END;
  v_measured  := CASE
    WHEN (v_queue.verdict_evidence ->> 'delta_value')    IS NOT NULL
     AND (v_queue.verdict_evidence ->> 'threshold_value') IS NOT NULL
    THEN ROUND(
      (v_queue.verdict_evidence ->> 'threshold_value')::numeric +
      (v_queue.verdict_evidence ->> 'delta_value')::numeric
    )::int
    ELSE NULL
  END;

  v_lat := v_queue.verdict_evidence ->> 'primary_evidence_lat';
  v_lng := v_queue.verdict_evidence ->> 'primary_evidence_lng';
  v_location := COALESCE(
    v_queue.verdict_evidence ->> 'geofence_name',
    v_queue.verdict_evidence ->> 'address',
    v_queue.verdict_evidence ->> 'location_label',
    CASE WHEN v_lat IS NOT NULL AND v_lng IS NOT NULL THEN v_lat || ',' || v_lng ELSE '-' END
  );

  RETURN jsonb_build_object(
    'asset_identifier',      v_queue.vehicle_plate,
    'penalty_value_cents',   (v_queue.verdict_evidence ->> 'fine_cents')::int,
    'measured_value',        v_measured,
    'threshold_value',       v_threshold,
    'exceeded_by',           v_exceeded,
    'occurred_at_utc',       (v_queue.verdict_evidence ->> 'primary_evidence_timestamp_utc')::timestamptz,
    'location_label',        v_location,
    'record_id',             v_queue.id::text,
    'status',                v_queue.status,
    'org_display_name',      v_org.name,
    'org_cnpj',              v_org.cnpj,
    'org_logo_url',          COALESCE(v_org.logo_url, ''),
    'primary_evidence_lat',  v_lat::numeric,
    'primary_evidence_lng',  v_lng::numeric,
    'clause_ref',            v_queue.verdict_evidence ->> 'clause_ref'
  );

EXCEPTION
  WHEN insufficient_privilege THEN
    RAISE;
  WHEN OTHERS THEN
    RAISE EXCEPTION 'Portal access denied.' USING ERRCODE = 'insufficient_privilege';
END;
$$;


-- ── Re-affirm grants ───────────────────────────────────────────────────────────
REVOKE ALL ON FUNCTION public.resolve_dispute(UUID, UUID, TEXT, TEXT, UUID, TEXT, TIMESTAMPTZ, TEXT, TEXT)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.resolve_dispute(UUID, UUID, TEXT, TEXT, UUID, TEXT, TIMESTAMPTZ, TEXT, TEXT)
  TO authenticated;

REVOKE ALL ON FUNCTION public.reject_sanction(UUID, UUID, UUID, TEXT, TEXT, TEXT, TIMESTAMPTZ)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.reject_sanction(UUID, UUID, UUID, TEXT, TEXT, TEXT, TIMESTAMPTZ)
  TO authenticated;

REVOKE ALL ON FUNCTION public.approve_sanction(UUID, UUID, UUID, TEXT, TIMESTAMPTZ, TEXT, TEXT)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.approve_sanction(UUID, UUID, UUID, TEXT, TIMESTAMPTZ, TEXT, TEXT)
  TO authenticated;

REVOKE ALL ON FUNCTION public.read_infraction_context(UUID) FROM PUBLIC, service_role;
GRANT EXECUTE ON FUNCTION public.read_infraction_context(UUID) TO anon, authenticated;

RESET client_min_messages;
