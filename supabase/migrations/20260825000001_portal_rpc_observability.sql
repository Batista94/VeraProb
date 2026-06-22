-- =============================================================================
-- Migration: portal RPC observability + hash idempotency — PKG1
--   (dispute portal submission esteira)
--
-- Problem: every business rejection AND every infra failure in the portal
-- submission path collapsed into a byte-identical opaque 42501 with NO machine-
-- parseable reason. The edge function then maps any failure to a 404 (INV-26),
-- so the server side was blind: SRE could not triage, and a transient retry
-- burned a max_submissions slot (no idempotency) permanently blocking a carrier.
--
-- This migration (Anti-Oracle preserved — message + ERRCODE unchanged):
--   A. DETAIL token (PORTAL_SUBMIT_REJECTED:<CODE>) on every RAISE in
--      create_portal_submission + submit_portal_justification_only. PostgREST
--      strips DETAIL for 42501 from the HTTP body — it reaches ONLY the
--      service_role edge function via error.details (Sentry). NEVER the carrier.
--   B. Hash idempotency in create_portal_submission keyed on
--      (token_id, sha256_client): a retry of the SAME bytes whose prior row is
--      still QUARANTINE (the network-failure-between-create-and-upload case)
--      reuses that row + path instead of consuming a new slot. The token is
--      validated FIRST (revoked/expired/scope), so a stale token still fails
--      opaquely even when the sha matches (INV-18 Zero-Trust).
--      Scope note: register_portal_evidence + submit_portal_justification_only
--      REVOKE the token on a successful finalize (20260820000002), so a row that
--      reached PENDING_AUDIT is unreachable via the same token (TOKEN_SOVEREIGNTY
--      guards it). Any OTHER prior state (e.g. a failed MISMATCH whose token is
--      still live) is NOT deduped — it falls through to a fresh submission with a
--      fresh quarantine path, so a sealed file is NEVER re-signed (INV-9).
--
-- create_portal_submission: rebuilt from its LATEST definition
-- (20260818000005); return shape UNCHANGED → CREATE OR REPLACE.
-- submit_portal_justification_only: rebuilt from its LATEST definition
-- (20260820000002 — which added the queue→pending_peer_review advance and the
-- one-shot token revocation; basing it on 818 would REGRESS those). Grants are
-- preserved by CREATE OR REPLACE; re-asserted defensively (INV-DATA-API-GRANT).
--
-- Council: Architect ✅ · Senior ✅ · QA-Security ✅ · Lead ✅
-- Invariants: INV-3, INV-9, INV-18, INV-22, INV-26, INV-DATA-API-GRANT.
-- =============================================================================
SET client_min_messages TO WARNING;

-- ── create_portal_submission — DETAIL tokens + QUARANTINE hash idempotency ───
CREATE OR REPLACE FUNCTION public.create_portal_submission(
  p_token            UUID,
  p_file_name        TEXT,
  p_mime_type        TEXT,
  p_file_size_bytes  BIGINT,
  p_sha256_client    TEXT,
  p_justification    TEXT,
  p_submitter_ip     TEXT  DEFAULT NULL,
  p_correlation_id   TEXT  DEFAULT NULL
)
RETURNS TABLE (submission_id UUID, quarantine_path TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_token         public.dispute_portal_tokens;
  v_queue         public.sanction_review_queue;
  v_ext           TEXT;
  v_count         INT;
  v_id            UUID := gen_random_uuid();
  v_path          TEXT;
  v_now           TIMESTAMPTZ := NOW();
  v_existing_id   UUID;
  v_existing_path TEXT;
BEGIN
  -- Timing normalization: lock both FOUND and NOT-FOUND paths.
  PERFORM pg_advisory_xact_lock(hashtextextended(p_token::text, 0));

  v_ext := public.portal_mime_ext(p_mime_type);
  IF v_ext IS NULL THEN
    RAISE EXCEPTION 'Submission rejected.'
      USING ERRCODE = 'insufficient_privilege', DETAIL = 'PORTAL_SUBMIT_REJECTED:MIME_UNSUPPORTED';
  END IF;
  IF p_file_size_bytes IS NULL OR p_file_size_bytes <= 0 OR p_file_size_bytes > 10485760 THEN
    RAISE EXCEPTION 'Submission rejected.'
      USING ERRCODE = 'insufficient_privilege', DETAIL = 'PORTAL_SUBMIT_REJECTED:FILE_SIZE_OUT_OF_RANGE';
  END IF;
  IF p_sha256_client IS NULL OR p_sha256_client !~ '^[a-f0-9]{64}$' THEN
    RAISE EXCEPTION 'Submission rejected.'
      USING ERRCODE = 'insufficient_privilege', DETAIL = 'PORTAL_SUBMIT_REJECTED:SHA256_INVALID';
  END IF;
  -- Justification is mandatory (testimony). Same opaque error (anti-oracle).
  -- trim() rejects all-whitespace input (char_length alone would admit "          ").
  IF p_justification IS NULL
     OR char_length(p_justification) > 4000
     OR char_length(trim(p_justification)) < 10
     OR p_justification ~ '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'
  THEN
    RAISE EXCEPTION 'Submission rejected.'
      USING ERRCODE = 'insufficient_privilege', DETAIL = 'PORTAL_SUBMIT_REJECTED:JUSTIFICATION_INVALID';
  END IF;

  SELECT * INTO v_token FROM public.dispute_portal_tokens
   WHERE token = p_token FOR UPDATE;
  -- Anti-oracle: token invalid / not submit-scoped / revoked / expired all alike.
  IF NOT FOUND
     OR v_token.token_scope <> 'submit'
     OR v_token.revoked_at_utc IS NOT NULL
     OR v_now > v_token.expires_at_utc
  THEN
    RAISE EXCEPTION 'Submission rejected.'
      USING ERRCODE = 'insufficient_privilege', DETAIL = 'PORTAL_SUBMIT_REJECTED:TOKEN_SOVEREIGNTY';
  END IF;

  SELECT * INTO v_queue FROM public.sanction_review_queue
   WHERE id = v_token.queue_entry_id AND organization_id = v_token.organization_id
   FOR SHARE;
  IF NOT FOUND OR v_queue.status <> 'disputed' THEN
    RAISE EXCEPTION 'Submission rejected.'
      USING ERRCODE = 'insufficient_privilege', DETAIL = 'PORTAL_SUBMIT_REJECTED:QUEUE_STATE_INVALID';
  END IF;

  -- Hash idempotency (INV-9 replay safety): a retry of the SAME bytes whose
  -- prior row is still QUARANTINE (upload never completed) reuses that row + path
  -- instead of consuming a slot. Runs AFTER token + queue validation so a revoked
  -- / expired token still fails opaquely (INV-18). Only QUARANTINE rows are
  -- reused — a non-QUARANTINE prior (e.g. MISMATCH) falls through to a fresh row
  -- with a fresh path, so a sealed file is never re-signed.
  SELECT id, quarantine_storage_path
    INTO v_existing_id, v_existing_path
   FROM public.portal_evidence_submissions
   WHERE token_id = v_token.id
     AND sha256_client = p_sha256_client
     AND status = 'QUARANTINE'
     AND deleted_at IS NULL
   ORDER BY submitted_at_utc ASC
   LIMIT 1;
  IF FOUND THEN
    submission_id := v_existing_id;
    quarantine_path := v_existing_path;
    RETURN NEXT;
    RETURN;
  END IF;

  -- Per-token submission cap (availability ceiling), race-free under the lock.
  SELECT count(*) INTO v_count FROM public.portal_evidence_submissions
   WHERE token_id = v_token.id AND deleted_at IS NULL;
  IF v_count >= v_token.max_submissions THEN
    RAISE EXCEPTION 'Submission rejected.'
      USING ERRCODE = 'insufficient_privilege', DETAIL = 'PORTAL_SUBMIT_REJECTED:SUBMISSION_CAP_EXCEEDED';
  END IF;

  v_path := v_token.id::text || '/' || v_id::text || '.' || v_ext;

  INSERT INTO public.portal_evidence_submissions
    (id, organization_id, queue_entry_id, token_id, quarantine_storage_path,
     file_name, mime_type_declared, file_size_bytes_declared, sha256_client,
     justification_text, submitter_ip, submitter_correlation_id, submitted_at_utc)
  VALUES
    (v_id, v_token.organization_id, v_token.queue_entry_id, v_token.id, v_path,
     p_file_name, p_mime_type, p_file_size_bytes, p_sha256_client,
     p_justification, p_submitter_ip::inet, p_correlation_id, v_now);

  INSERT INTO public.sla_audit_ledger_v2
    (organization_id, type, operator_id, set_id, contract_id, plan_version, payload, occurred_at_utc)
  VALUES (
    v_token.organization_id, 'PORTAL_EVIDENCE_SUBMITTED', 'PORTAL',
    v_queue.set_id, v_queue.contract_id::uuid, 0,
    jsonb_build_object(
      'queue_entry_id', v_token.queue_entry_id,
      'token_id', v_token.id,
      'submission_id', v_id,
      'sha256_client', p_sha256_client,
      'mime_type_declared', p_mime_type,
      'file_size_bytes_declared', p_file_size_bytes,
      -- Hash, not raw text: the ledger is auditable; testimony stays in the row.
      'justification_sha256', encode(extensions.digest(p_justification, 'sha256'), 'hex')
    ),
    v_now
  );

  submission_id := v_id;
  quarantine_path := v_path;
  RETURN NEXT;
END;
$$;

-- ── submit_portal_justification_only — DETAIL tokens (base: 20260820000002) ───
-- Latest body advances the queue to pending_peer_review and revokes the token on
-- success; both are preserved here verbatim, with DETAIL tokens added.
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
    RAISE EXCEPTION 'Submission rejected.'
      USING ERRCODE = 'insufficient_privilege', DETAIL = 'PORTAL_SUBMIT_REJECTED:JUSTIFICATION_INVALID';
  END IF;

  SELECT * INTO v_token FROM public.dispute_portal_tokens
   WHERE token = p_token FOR UPDATE;
  IF NOT FOUND
     OR v_token.token_scope <> 'submit'
     OR v_token.revoked_at_utc IS NOT NULL
     OR v_now > v_token.expires_at_utc
  THEN
    RAISE EXCEPTION 'Submission rejected.'
      USING ERRCODE = 'insufficient_privilege', DETAIL = 'PORTAL_SUBMIT_REJECTED:TOKEN_SOVEREIGNTY';
  END IF;

  SELECT * INTO v_queue FROM public.sanction_review_queue
   WHERE id = v_token.queue_entry_id AND organization_id = v_token.organization_id
   FOR SHARE;
  IF NOT FOUND OR v_queue.status <> 'disputed' THEN
    RAISE EXCEPTION 'Submission rejected.'
      USING ERRCODE = 'insufficient_privilege', DETAIL = 'PORTAL_SUBMIT_REJECTED:QUEUE_STATE_INVALID';
  END IF;

  -- Per-token cap counts file + justification-only submissions together.
  SELECT
    (SELECT count(*) FROM public.portal_evidence_submissions
      WHERE token_id = v_token.id AND deleted_at IS NULL)
    + (SELECT count(*) FROM public.portal_justification_submissions
      WHERE token_id = v_token.id AND deleted_at IS NULL)
  INTO v_count;
  IF v_count >= v_token.max_submissions THEN
    RAISE EXCEPTION 'Submission rejected.'
      USING ERRCODE = 'insufficient_privilege', DETAIL = 'PORTAL_SUBMIT_REJECTED:SUBMISSION_CAP_EXCEEDED';
  END IF;

  v_seal := encode(extensions.digest(p_justification, 'sha256'), 'hex');

  INSERT INTO public.portal_justification_submissions
    (organization_id, queue_entry_id, token_id, justification_text,
     sha256_justification_seal, submitted_at_utc)
  VALUES
    (v_token.organization_id, v_token.queue_entry_id, v_token.id, p_justification,
     v_seal, v_now)
  RETURNING id INTO v_id;

  -- Strict concurrency control: advance queue state only if still 'disputed'.
  UPDATE public.sanction_review_queue
     SET status = 'pending_peer_review'
   WHERE id = v_queue.id AND status = 'disputed';

  GET DIAGNOSTICS v_rows_affected = ROW_COUNT;
  IF v_rows_affected = 0 THEN
    RAISE EXCEPTION 'Sanction no longer in disputed state.'
      USING ERRCODE = 'insufficient_privilege', DETAIL = 'PORTAL_SUBMIT_REJECTED:QUEUE_STATE_RACE';
  END IF;

  -- Revoke token to prevent double-submit.
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

-- ── Grants (INV-DATA-API-GRANT) — re-assert defensively (service_role-only) ───
REVOKE ALL ON FUNCTION public.create_portal_submission(UUID,TEXT,TEXT,BIGINT,TEXT,TEXT,TEXT,TEXT)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_portal_submission(UUID,TEXT,TEXT,BIGINT,TEXT,TEXT,TEXT,TEXT)
  TO service_role;

REVOKE ALL ON FUNCTION public.submit_portal_justification_only(UUID,TEXT)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.submit_portal_justification_only(UUID,TEXT)
  TO service_role;

RESET client_min_messages;
