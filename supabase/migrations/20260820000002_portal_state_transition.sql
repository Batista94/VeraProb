-- =============================================================================
-- Migration: portal_state_transition — Fix Portal Dispute Submissions
-- Purpose:   Updates register_portal_evidence and submit_portal_justification_only
--            to transition sanction_review_queue to 'pending_peer_review'
--            and revoke the token to prevent double-submissions.
--            Implements strict concurrency checks (WHERE status = 'disputed').
-- =============================================================================

SET client_min_messages TO 'WARNING';

-- ── 1. register_portal_evidence ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.register_portal_evidence(
  p_submission_id          UUID,
  p_sha256_server          TEXT,
  p_mime_type_detected     TEXT,
  p_file_size_bytes_actual BIGINT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_sub           public.portal_evidence_submissions;
  v_queue         public.sanction_review_queue;
  v_ext           TEXT;
  v_path          TEXT;
  v_count         INT;
  v_id            UUID;
  v_combined_seal TEXT;
  v_now           TIMESTAMPTZ := NOW();
  v_rows_affected INT;
BEGIN
  IF p_sha256_server IS NULL OR p_sha256_server !~ '^[a-f0-9]{64}$' THEN
    RAISE EXCEPTION 'Evidence rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  v_ext := public.portal_mime_ext(p_mime_type_detected);
  IF v_ext IS NULL THEN
    RAISE EXCEPTION 'Evidence rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_sub FROM public.portal_evidence_submissions
   WHERE id = p_submission_id FOR UPDATE;
  IF NOT FOUND OR v_sub.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'Evidence rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended(v_sub.organization_id::text || '/' || v_sub.queue_entry_id::text, 0)
  );

  -- Idempotent replay: already finalized → return the existing attachment.
  IF v_sub.status = 'PENDING_AUDIT' THEN
    SELECT id INTO v_id FROM public.dispute_evidence_attachments
     WHERE submission_id = p_submission_id AND deleted_at IS NULL
     LIMIT 1;
    IF v_id IS NOT NULL THEN
      RETURN v_id;
    END IF;
  ELSIF v_sub.status <> 'QUARANTINE' THEN
    RAISE EXCEPTION 'Evidence rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_queue FROM public.sanction_review_queue
   WHERE id = v_sub.queue_entry_id AND organization_id = v_sub.organization_id
   FOR SHARE;
  IF NOT FOUND OR v_queue.status <> 'disputed' THEN
    RAISE EXCEPTION 'Evidence rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT count(*) INTO v_count FROM public.dispute_evidence_attachments
   WHERE organization_id = v_sub.organization_id
     AND queue_entry_id = v_sub.queue_entry_id
     AND deleted_at IS NULL;
  IF v_count >= 10 THEN
    RAISE EXCEPTION 'Evidence attachment limit reached.'
      USING ERRCODE = 'P0001', DETAIL = 'IntegrityException';
  END IF;

  -- Production path derived from SEALED fields (never carrier input).
  v_path := v_sub.organization_id::text || '/' || v_sub.queue_entry_id::text
            || '/' || v_sub.id::text || '.' || v_ext;

  v_combined_seal := encode(
    extensions.digest(p_sha256_server || ':' || v_sub.justification_text, 'sha256'),
    'hex'
  );

  BEGIN
    INSERT INTO public.dispute_evidence_attachments
      (organization_id, queue_entry_id, storage_path, file_name, mime_type,
       file_size_bytes, sha256_hash, sha256_combined_seal, verification_status,
       hash_verified_at, uploaded_by, submission_id, attached_at)
    VALUES
      (v_sub.organization_id, v_sub.queue_entry_id, v_path, v_sub.file_name,
       p_mime_type_detected, p_file_size_bytes_actual, p_sha256_server,
       v_combined_seal, 'VERIFIED', v_now, NULL, v_sub.id, v_now)
    RETURNING id INTO v_id;
  EXCEPTION WHEN unique_violation THEN
    -- Same bytes already attached for this dispute — reuse it (idempotent).
    SELECT id INTO v_id FROM public.dispute_evidence_attachments
     WHERE organization_id = v_sub.organization_id
       AND queue_entry_id = v_sub.queue_entry_id
       AND sha256_hash = p_sha256_server
     LIMIT 1;
  END;

  UPDATE public.portal_evidence_submissions
     SET status = 'PENDING_AUDIT',
         production_storage_path = v_path,
         mime_type_detected = p_mime_type_detected,
         file_size_bytes_actual = p_file_size_bytes_actual,
         sha256_server = p_sha256_server,
         finalized_at_utc = v_now
   WHERE id = v_sub.id;

  -- [NEW] Strict Concurrency Control: Advance queue state only if still 'disputed'
  UPDATE public.sanction_review_queue
     SET status = 'pending_peer_review'
   WHERE id = v_queue.id AND status = 'disputed';
  
  GET DIAGNOSTICS v_rows_affected = ROW_COUNT;
  IF v_rows_affected = 0 THEN
    RAISE EXCEPTION 'Sanction no longer in disputed state.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- [NEW] Revoke token to prevent double-submit
  UPDATE public.dispute_portal_tokens
     SET revoked_at_utc = v_now
   WHERE id = v_sub.token_id AND revoked_at_utc IS NULL;

  INSERT INTO public.sla_audit_ledger_v2
    (organization_id, type, operator_id, set_id, contract_id, plan_version, payload, occurred_at_utc)
  VALUES (
    v_sub.organization_id, 'PORTAL_EVIDENCE_FINALIZED', 'PORTAL',
    v_queue.set_id, v_queue.contract_id::uuid, 0,
    jsonb_build_object(
      'queue_entry_id', v_sub.queue_entry_id,
      'submission_id', v_sub.id,
      'attachment_id', v_id,
      'sha256_server', p_sha256_server,
      'sha256_combined_seal', v_combined_seal
    ),
    v_now
  );

  RETURN v_id;
END;
$$;

-- ── 2. submit_portal_justification_only ─────────────────────────────────────
CREATE OR REPLACE FUNCTION public.submit_portal_justification_only(
  p_token         UUID,
  p_justification TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_token         public.dispute_portal_tokens;
  v_queue         public.sanction_review_queue;
  v_count         INT;
  v_id            UUID;
  v_seal          TEXT;
  v_now           TIMESTAMPTZ := NOW();
  v_rows_affected INT;
BEGIN
  -- Timing normalization: lock both FOUND and NOT-FOUND paths.
  PERFORM pg_advisory_xact_lock(hashtextextended(p_token::text, 0));

  -- Justification is the whole submission here — mandatory + valid (anti-oracle).
  IF p_justification IS NULL
     OR char_length(p_justification) > 4000
     OR char_length(trim(p_justification)) < 10
     OR p_justification ~ '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'
  THEN
    RAISE EXCEPTION 'Submission rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_token FROM public.dispute_portal_tokens
   WHERE token = p_token FOR UPDATE;
  IF NOT FOUND
     OR v_token.token_scope <> 'submit'
     OR v_token.revoked_at_utc IS NOT NULL
     OR v_now > v_token.expires_at_utc
  THEN
    RAISE EXCEPTION 'Submission rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_queue FROM public.sanction_review_queue
   WHERE id = v_token.queue_entry_id AND organization_id = v_token.organization_id
   FOR SHARE;
  IF NOT FOUND OR v_queue.status <> 'disputed' THEN
    RAISE EXCEPTION 'Submission rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Per-token cap counts file + justification-only submissions together.
  SELECT
    (SELECT count(*) FROM public.portal_evidence_submissions
      WHERE token_id = v_token.id AND deleted_at IS NULL)
    + (SELECT count(*) FROM public.portal_justification_submissions
      WHERE token_id = v_token.id AND deleted_at IS NULL)
  INTO v_count;
  IF v_count >= v_token.max_submissions THEN
    RAISE EXCEPTION 'Submission rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  v_seal := encode(extensions.digest(p_justification, 'sha256'), 'hex');

  INSERT INTO public.portal_justification_submissions
    (organization_id, queue_entry_id, token_id, justification_text,
     sha256_justification_seal, submitted_at_utc)
  VALUES
    (v_token.organization_id, v_token.queue_entry_id, v_token.id, p_justification,
     v_seal, v_now)
  RETURNING id INTO v_id;

  -- [NEW] Strict Concurrency Control: Advance queue state only if still 'disputed'
  UPDATE public.sanction_review_queue
     SET status = 'pending_peer_review'
   WHERE id = v_queue.id AND status = 'disputed';
  
  GET DIAGNOSTICS v_rows_affected = ROW_COUNT;
  IF v_rows_affected = 0 THEN
    RAISE EXCEPTION 'Sanction no longer in disputed state.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- [NEW] Revoke token to prevent double-submit
  UPDATE public.dispute_portal_tokens
     SET revoked_at_utc = v_now
   WHERE id = v_token.id AND revoked_at_utc IS NULL;

  INSERT INTO public.sla_audit_ledger_v2
    (organization_id, type, operator_id, set_id, contract_id, plan_version, payload, occurred_at_utc)
  VALUES (
    v_token.organization_id, 'PORTAL_JUSTIFICATION_SUBMITTED', 'PORTAL',
    v_queue.set_id, v_queue.contract_id::uuid, 0,
    jsonb_build_object(
      'queue_entry_id', v_token.queue_entry_id,
      'token_id', v_token.id,
      'pjs_id', v_id,
      'sha256_justification_seal', v_seal
    ),
    v_now
  );

  RETURN v_id;
END;
$$;

RESET client_min_messages;
