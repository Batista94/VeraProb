-- =============================================================================
-- Migration: portal_no_status_flip_and_alert
--
-- Problem (forensic integrity + operator notification):
--   register_portal_evidence and submit_portal_justification_only ILLEGALLY
--   flipped sanction_review_queue.status 'disputed' → 'pending_peer_review' on a
--   carrier submission, WITHOUT setting peer_review_proposed_action /
--   peer_review_expires_at. That ejected the card from the "Aguardando Evidência"
--   stream (filters status='disputed') and produced a ZOMBIE: confirm_peer_review
--   hits the ELSE→42501 (un-confirmable) and expire_stale_peer_reviews skips it
--   (WHERE peer_review_expires_at IS NOT NULL). The dispute became irresolvible and
--   the evidence unreachable ("aparece em pendentes e depois some"). A carrier
--   submission is NOT a peer-review proposal — only an auditor's dual-control
--   action may move the queue to pending_peer_review.
--
--   Additionally, neither RPC notified the operator: nothing landed in
--   operational_alerts, so the submission never surfaced in the triage drawer.
--
-- Fix (additive CREATE OR REPLACE — no merged migration modified):
--   A. Widen valid_alert_type to admit DISPUTE_DEFENSE_SUBMITTED (zero-downtime:
--      ADD NOT VALID → VALIDATE → DROP old → RENAME back to the canonical name so
--      committed tests asserting 'valid_alert_type' keep passing).
--   B. register_portal_evidence (rebased on its LATEST def, 20260820000002):
--      REMOVE the queue flip + GET DIAGNOSTICS guard — the queue STAYS 'disputed'.
--      KEEP the one-shot token revocation (sufficient anti-double-submit guard).
--      Capture the PORTAL_EVIDENCE_FINALIZED ledger id and emit a
--      DISPUTE_DEFENSE_SUBMITTED operational_alert (metadata only — no raw
--      testimony; ledger stays hash-only, INV-3/9). Idempotent via
--      unique_alert_per_event (ON CONFLICT DO NOTHING).
--   C. submit_portal_justification_only (rebased on its LATEST def,
--      20260825000001 — preserves the DETAIL tokens): same flip removal + alert,
--      defense_type='text', filename NULL.
--
-- Council: Architect ✅ · Senior ✅ · QA-Security ✅ · Lead ✅
-- Invariants: INV-1, INV-3, INV-9, INV-18, INV-22, INV-26, INV-DATA-API-GRANT.
-- =============================================================================
-- pr_scanner: ignore-regression
--   Council-approved: additive CREATE OR REPLACE of two portal RPCs to REMOVE an
--   illegal state transition that bricked disputes; no merged migration is edited.
SET client_min_messages TO 'WARNING';

-- ── A. Widen valid_alert_type (zero-downtime + rename-back) ───────────────────
ALTER TABLE public.operational_alerts
  ADD CONSTRAINT chk_alert_type_v2 CHECK (
    alert_type IN (
      'NO_SHOW',
      'EVIDENCE_GAP',
      'PENALTY_APPLIED',
      'TELEGRAM_ORPHAN',
      'SLA_BREACH',
      'DEVIATION',
      'POTENTIAL_TIME_FRAUD',
      'DISPUTE_DEFENSE_SUBMITTED'
    )
  ) NOT VALID;

ALTER TABLE public.operational_alerts
  VALIDATE CONSTRAINT chk_alert_type_v2;

-- INV-DB: zero-downtime-verified
-- The old constraint is a strict subset of chk_alert_type_v2 (already VALIDATEd),
-- so dropping it never leaves a window where an invalid row could be admitted.
ALTER TABLE public.operational_alerts
  DROP CONSTRAINT valid_alert_type;

ALTER TABLE public.operational_alerts
  RENAME CONSTRAINT chk_alert_type_v2 TO valid_alert_type;

-- ── A2. Exempt DISPUTE_DEFENSE_SUBMITTED from the driver_id attribution guard ──
-- chk_alert_driver_attribution (20260818000004, INV-18) forces a non-empty
-- context.driver_id on every alert type except TELEGRAM_ORPHAN. A dispute-defense
-- alert is SANCTION-bound, not raw-telemetry-driver-bound: it is already fully
-- attributed via queue lineage (queue_entry_id + vehicle_plate + driver_name), and
-- sanction_review_queue stores no registry driver_id to surface. Exempt it like
-- TELEGRAM_ORPHAN (zero-downtime + rename-back to the canonical name).
ALTER TABLE public.operational_alerts
  ADD CONSTRAINT chk_alert_driver_attribution_v2 CHECK (
    alert_type IN ('TELEGRAM_ORPHAN', 'DISPUTE_DEFENSE_SUBMITTED')
    OR (
      (context ? 'driver_id')
      AND (context ->> 'driver_id') IS NOT NULL
      AND (context ->> 'driver_id') <> ''
    )
  ) NOT VALID;

-- INV-DB: zero-downtime-verified
-- Mirror the original NOT VALID status (20260818000004): the predicate guards new
-- inserts without scanning history (older rows predate driver attribution; a
-- VALIDATE could even fail on them). v2 is strictly more permissive than the old
-- predicate (one extra exempt type), so swapping them never rejects a row the old
-- constraint admitted, and convalidated stays false.
ALTER TABLE public.operational_alerts
  DROP CONSTRAINT chk_alert_driver_attribution;

ALTER TABLE public.operational_alerts
  RENAME CONSTRAINT chk_alert_driver_attribution_v2 TO chk_alert_driver_attribution;

-- ── B. register_portal_evidence — no flip + operator alert ────────────────────
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
  v_ledger_id     UUID;
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

  -- Queue STAYS 'disputed': a carrier submission is NOT a peer-review proposal.
  -- The card remains in "Aguardando Evidência" for the auditor to weigh.

  -- One-shot token revocation prevents a double submit (sufficient guard).
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
  )
  RETURNING id INTO v_ledger_id;

  -- Notify the operator in the triage drawer (metadata only — INV-3/9: the raw
  -- testimony never enters the alert; it is read via the sealed submission row).
  INSERT INTO public.operational_alerts
    (organization_id, entity_id, contract_id, alert_type, severity,
     triggering_event_id, context)
  VALUES (
    v_sub.organization_id,
    COALESCE(v_queue.vehicle_plate, v_queue.set_id),
    v_queue.contract_id,
    'DISPUTE_DEFENSE_SUBMITTED',
    'HIGH',
    v_ledger_id,
    jsonb_build_object(
      'queue_entry_id', v_queue.id,
      'vehicle_plate', v_queue.vehicle_plate,
      'driver_name', v_queue.operator_name,
      'fine_amount_cents', COALESCE((v_queue.verdict_evidence ->> 'fine_cents')::bigint, 0),
      'defense_type', 'file',
      'filename', v_sub.file_name
    )
  )
  ON CONFLICT (triggering_event_id, alert_type) DO NOTHING;

  RETURN v_id;
END;
$$;

-- ── C. submit_portal_justification_only — no flip + operator alert ────────────
-- Base: 20260825000001 (DETAIL tokens preserved). Removes the queue flip + the
-- QUEUE_STATE_RACE guard; the queue STAYS 'disputed'.
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
  v_ledger_id     UUID;
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

  -- Queue STAYS 'disputed' (see register_portal_evidence rationale).

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
  )
  RETURNING id INTO v_ledger_id;

  -- Notify the operator (metadata only; text defense has no file).
  INSERT INTO public.operational_alerts
    (organization_id, entity_id, contract_id, alert_type, severity,
     triggering_event_id, context)
  VALUES (
    v_token.organization_id,
    COALESCE(v_queue.vehicle_plate, v_queue.set_id),
    v_queue.contract_id,
    'DISPUTE_DEFENSE_SUBMITTED',
    'HIGH',
    v_ledger_id,
    jsonb_build_object(
      'queue_entry_id', v_queue.id,
      'vehicle_plate', v_queue.vehicle_plate,
      'driver_name', v_queue.operator_name,
      'fine_amount_cents', COALESCE((v_queue.verdict_evidence ->> 'fine_cents')::bigint, 0),
      'defense_type', 'text',
      'filename', NULL
    )
  )
  ON CONFLICT (triggering_event_id, alert_type) DO NOTHING;

  RETURN v_id;
END;
$$;

-- ── Grants (INV-DATA-API-GRANT) — re-assert defensively (service_role-only) ───
REVOKE ALL ON FUNCTION public.register_portal_evidence(UUID,TEXT,TEXT,BIGINT)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.register_portal_evidence(UUID,TEXT,TEXT,BIGINT)
  TO service_role;

REVOKE ALL ON FUNCTION public.submit_portal_justification_only(UUID,TEXT)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.submit_portal_justification_only(UUID,TEXT)
  TO service_role;

RESET client_min_messages;
