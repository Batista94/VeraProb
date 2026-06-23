-- =============================================================================
-- Migration: defense_submitted_at
--
-- Problem (auditor UX — false tab signal):
--   After a carrier submits its contestation+evidence through the portal link,
--   the queue STAYS 'disputed' (correct, per 20260827000001 — a flip would mint a
--   zombie). But the card then sits forever under the "Aguardando Evidência" tab,
--   which is a false claim: the evidence already arrived; what is actually pending
--   is the AUDITOR's verdict. The auditor cannot tell at list-scan time which
--   disputed cards already have a defense on file.
--
-- Fix (additive CREATE OR REPLACE — no merged migration modified):
--   A denormalized write-once timestamp on the queue row, set the moment the
--   carrier submits (file OR text defense). The realtime stream is keyed on the
--   queue row, so writing this column fires a client update; the UI re-labels the
--   card ("DEFESA RECEBIDA") and sorts it to the top WITHOUT a status flip.
--
--   A. ADD COLUMN sanction_review_queue.defense_submitted_at (nullable, NO DEFAULT
--      — server-derived only; historical disputed rows stay NULL → correctly read
--      as "still awaiting"). Metadata-only ALTER (instant, zero-downtime).
--   B. register_portal_evidence — rebased on its LATEST def (20260827000001).
--      Deltas vs base: queue lock FOR SHARE → FOR UPDATE; set defense_submitted_at
--      (IS NULL guard → first submission wins, idempotent on replay). Queue stays
--      'disputed'. Everything else byte-identical to the base.
--   C. submit_portal_justification_only — same two deltas.
--   D. prevent_srq_immutable_mutation — rebased on its LATEST def (20260817000004).
--      Adds a write-once guard: once defense_submitted_at is set it can never be
--      changed/cleared (closes the anti-forensic exploit of an auditor hiding a
--      received defense by re-routing the card back to "Aguardando Evidência").
--
-- Council: Architect ✅ · Senior ✅ · QA-Security ✅ · Lead ✅
-- Invariants: INV-1, INV-3, INV-6, INV-18, INV-22, INV-26, INV-DATA-API-GRANT.
-- Depends on: 20260827000001 (latest portal RPC defs), 20260817000004 (latest
--             prevent_srq_immutable_mutation def).
-- =============================================================================
-- pr_scanner: ignore-regression
--   Council-approved: additive CREATE OR REPLACE of two portal RPCs + the SRQ
--   immutability trigger to denormalize a write-once UX signal. No merged
--   migration is edited; queue status semantics are unchanged (stays 'disputed').
SET client_min_messages TO 'WARNING';

-- ── A. Column (nullable, NO DEFAULT — INV-6: server-derived, never device clock) ─
ALTER TABLE public.sanction_review_queue
  ADD COLUMN IF NOT EXISTS defense_submitted_at TIMESTAMPTZ;

COMMENT ON COLUMN public.sanction_review_queue.defense_submitted_at IS
  'Write-once UTC instant the carrier first submitted a portal defense (file or text). '
  'NULL = still awaiting submission. Drives the "DEFESA RECEBIDA" badge + sort. '
  'Queue status stays disputed (no flip). Sealed by prevent_srq_immutable_mutation (INV-18).';

-- ── B. register_portal_evidence — rebased on 20260827000001 + defense_submitted_at ─
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

  -- Delta vs base: FOR SHARE → FOR UPDATE (we now write defense_submitted_at back).
  SELECT * INTO v_queue FROM public.sanction_review_queue
   WHERE id = v_sub.queue_entry_id AND organization_id = v_sub.organization_id
   FOR UPDATE;
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

  -- Queue STAYS 'disputed' (a carrier submission is NOT a peer-review proposal).
  -- Delta vs base: stamp the write-once defense signal so the card re-labels to
  -- "DEFESA RECEBIDA" and sorts to the top of the disputed lane. IS NULL guard →
  -- first submission wins; replays / later submissions never advance it.
  UPDATE public.sanction_review_queue
     SET defense_submitted_at = v_now
   WHERE id = v_queue.id AND defense_submitted_at IS NULL;

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

-- ── C. submit_portal_justification_only — rebased on 20260827000001 + signal ───
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

  -- Delta vs base: FOR SHARE → FOR UPDATE (we now write defense_submitted_at back).
  SELECT * INTO v_queue FROM public.sanction_review_queue
   WHERE id = v_token.queue_entry_id AND organization_id = v_token.organization_id
   FOR UPDATE;
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
  -- Delta vs base: stamp the write-once defense signal (IS NULL guard, idempotent).
  UPDATE public.sanction_review_queue
     SET defense_submitted_at = v_now
   WHERE id = v_queue.id AND defense_submitted_at IS NULL;

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

-- ── D. prevent_srq_immutable_mutation — rebased on 20260817000004 + write-once ─
-- Adds a write-once seal on defense_submitted_at: once set it can never change or
-- be cleared. Closes the exploit where an auditor with RLS UPDATE access clears
-- the column to hide a received defense and issue a "no defense" verdict (INV-18).
CREATE OR REPLACE FUNCTION public.prevent_srq_immutable_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.organization_id   IS DISTINCT FROM OLD.organization_id   OR
     NEW.ledger_entry_id   IS DISTINCT FROM OLD.ledger_entry_id   OR
     NEW.set_id            IS DISTINCT FROM OLD.set_id            OR
     NEW.contract_id       IS DISTINCT FROM OLD.contract_id       OR
     NEW.verdict_evidence  IS DISTINCT FROM OLD.verdict_evidence  OR
     NEW.created_at        IS DISTINCT FROM OLD.created_at        OR
     NEW.vehicle_plate     IS DISTINCT FROM OLD.vehicle_plate     OR
     NEW.operator_name     IS DISTINCT FROM OLD.operator_name
  THEN
    RAISE EXCEPTION
      'sanction_review_queue: immutable field mutation attempted (INV-1). id: %', OLD.id
    USING ERRCODE = 'restrict_violation';
  END IF;

  -- 'acknowledged' is a terminal status: the debt is conceded, no transition out.
  IF OLD.status = 'acknowledged' AND NEW.status IS DISTINCT FROM OLD.status THEN
    RAISE EXCEPTION
      'sanction_review_queue: acknowledged is terminal — no transition (INV-3). id: %', OLD.id
    USING ERRCODE = 'restrict_violation';
  END IF;

  -- defense_submitted_at is write-once: a received defense can never be un-received.
  IF OLD.defense_submitted_at IS NOT NULL
     AND NEW.defense_submitted_at IS DISTINCT FROM OLD.defense_submitted_at THEN
    RAISE EXCEPTION
      'sanction_review_queue: defense_submitted_at is write-once (INV-18). id: %', OLD.id
    USING ERRCODE = 'restrict_violation';
  END IF;

  RETURN NEW;
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
