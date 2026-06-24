-- =============================================================================
-- Migration: portal_submission_rpcs_ledger — Sprint A (Portal + De Acordo) M5
-- Purpose:   Wires the portal counter-evidence pipeline and the acknowledgement
--            ("De Acordo") flow. All state mutations are encapsulated in atomic
--            SECURITY DEFINER RPCs (row + ledger fact in one transaction) so the
--            edge functions stay thin orchestrators and every path is pgTAP-
--            testable without Deno.
--
-- Pipeline (each step one RPC):
--   create_portal_submission   (service_role) — mint QUARANTINE row + signed-URL path
--   register_portal_evidence   (service_role) — finalize OK: attach + PENDING_AUDIT
--   fail_portal_submission     (service_role) — finalize fail: MISMATCH/REJECTED
--   audit_portal_submission    (authenticated) — auditor ACCEPT/REJECT
--   acknowledge_via_portal     (anon+auth)    — carrier De Acordo (hash-bound)
--   acknowledge_sanction_internal (auth)      — off-band De Acordo (no hash)
--
-- Council: Architect ✅ · Senior ✅ · QA-Security ✅ · Business ✅ · Lead ✅
-- Invariants: INV-1, INV-2, INV-3, INV-6, INV-9, INV-18, INV-22, INV-26.
-- Depends on: M2 (submissions), M3 (bucket), M4 (acknowledgements),
--             20260813000001 (dea), 20260814000003 (read_dispute_portal).
-- =============================================================================

SET client_min_messages TO 'WARNING';

-- ── 1. dispute_evidence_attachments: portal provenance ───────────────────────
-- Portal-originated attachments have no human uploader (uploaded_by NULL) and
-- link back to their quarantine submission (full chain of custody:
-- attachment → submission → token → carrier). DROP NOT NULL is metadata-only.

ALTER TABLE public.dispute_evidence_attachments
  ALTER COLUMN uploaded_by DROP NOT NULL;

ALTER TABLE public.dispute_evidence_attachments
  ADD COLUMN IF NOT EXISTS submission_id UUID
    REFERENCES public.portal_evidence_submissions(id);

COMMENT ON COLUMN public.dispute_evidence_attachments.submission_id IS
  'Portal provenance: links to the quarantine submission. NULL for direct uploads. Sealed (INV-3).';

-- Seal submission_id in the existing immutability trigger (re-derive full body).
CREATE OR REPLACE FUNCTION public.prevent_dea_immutable_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.organization_id IS DISTINCT FROM OLD.organization_id OR
     NEW.queue_entry_id   IS DISTINCT FROM OLD.queue_entry_id  OR
     NEW.storage_path     IS DISTINCT FROM OLD.storage_path    OR
     NEW.sha256_hash      IS DISTINCT FROM OLD.sha256_hash     OR
     NEW.file_name        IS DISTINCT FROM OLD.file_name       OR
     NEW.mime_type        IS DISTINCT FROM OLD.mime_type       OR
     NEW.file_size_bytes  IS DISTINCT FROM OLD.file_size_bytes OR
     NEW.uploaded_by      IS DISTINCT FROM OLD.uploaded_by     OR
     NEW.submission_id    IS DISTINCT FROM OLD.submission_id   OR
     NEW.attached_at      IS DISTINCT FROM OLD.attached_at
  THEN
    RAISE EXCEPTION
      'dispute_evidence_attachments: immutable field mutation (INV-9). id: %', OLD.id
    USING ERRCODE = 'restrict_violation';
  END IF;

  IF OLD.deleted_at IS NOT NULL AND NEW.deleted_at IS NULL THEN
    RAISE EXCEPTION
      'dispute_evidence_attachments: cannot resurrect soft-deleted evidence (INV-3). id: %', OLD.id
    USING ERRCODE = 'restrict_violation';
  END IF;

  RETURN NEW;
END;
$$;

-- ── 2. Widen chk_ledger_type (H1 swap → canonical name preserved) ────────────
ALTER TABLE public.sla_audit_ledger_v2
  ADD CONSTRAINT chk_ledger_type_v5 CHECK (type IN (
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
    'DUAL_CONTROL_THRESHOLD_CHANGED','DISPUTE_EVIDENCE_ATTACHED','DISPUTE_SLA_BREACHED',
    'EVIDENCE_HASH_MISMATCH','DISPUTE_PORTAL_TOKEN_GENERATED','DISPUTE_PORTAL_TOKEN_ACCESSED',
    'DISPUTE_PORTAL_TOKEN_REVOKED','RULE_SCHEDULED','RULE_ACTIVATED','RULE_RETIRED',
    'CONTRACT_FINANCIAL_TERMS_AMENDED',
    -- Sprint A (Portal Submissão + De Acordo)
    'PORTAL_EVIDENCE_SUBMITTED','PORTAL_EVIDENCE_FINALIZED','PORTAL_EVIDENCE_HASH_MISMATCH',
    'PORTAL_EVIDENCE_MIME_MISMATCH','PORTAL_EVIDENCE_REJECTED',
    'PORTAL_EVIDENCE_AUDITOR_ACCEPTED','PORTAL_EVIDENCE_AUDITOR_REJECTED',
    'SANCTION_ACKNOWLEDGED'
  )) NOT VALID; -- INV-DB: zero-downtime-verified (superset; existing rows conform)
ALTER TABLE public.sla_audit_ledger_v2 VALIDATE CONSTRAINT chk_ledger_type_v5;
ALTER TABLE public.sla_audit_ledger_v2 DROP CONSTRAINT IF EXISTS chk_ledger_type; -- INV-DB: zero-downtime-verified (CHECK swap)
ALTER TABLE public.sla_audit_ledger_v2 RENAME CONSTRAINT chk_ledger_type_v5 TO chk_ledger_type;

-- ── 3. Helper: canonical mime → file extension (immutable) ───────────────────
CREATE OR REPLACE FUNCTION public.portal_mime_ext(p_mime TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE p_mime
    WHEN 'image/jpeg'      THEN 'jpg'
    WHEN 'image/png'       THEN 'png'
    WHEN 'application/pdf' THEN 'pdf'
    WHEN 'image/heic'      THEN 'heic'
    WHEN 'image/heif'      THEN 'heif'
    WHEN 'image/webp'      THEN 'webp'
    ELSE NULL
  END;
$$;

-- ── 4. create_portal_submission (service_role) ───────────────────────────────
-- Mints a QUARANTINE row for a submit-scoped token under the per-token cap, and
-- returns the submission id + quarantine path the edge fn signs an upload URL for.
-- The quarantine path carries NO org_id (anti-inference): {token_id}/{uuid}.ext.
CREATE OR REPLACE FUNCTION public.create_portal_submission(
  p_token            UUID,
  p_file_name        TEXT,
  p_mime_type        TEXT,
  p_file_size_bytes  BIGINT,
  p_sha256_client    TEXT,
  p_submitter_ip     TEXT  DEFAULT NULL,
  p_correlation_id   TEXT  DEFAULT NULL
)
RETURNS TABLE (submission_id UUID, quarantine_path TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_token  public.dispute_portal_tokens;
  v_queue  public.sanction_review_queue;
  v_ext    TEXT;
  v_count  INT;
  v_id     UUID := gen_random_uuid();
  v_path   TEXT;
  v_now    TIMESTAMPTZ := NOW();
BEGIN
  -- Timing normalization (same idiom as read_dispute_portal): lock both the
  -- FOUND and NOT-FOUND paths so latency cannot disclose token validity.
  PERFORM pg_advisory_xact_lock(hashtextextended(p_token::text, 0));

  v_ext := public.portal_mime_ext(p_mime_type);
  IF v_ext IS NULL THEN
    RAISE EXCEPTION 'Submission rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_file_size_bytes IS NULL OR p_file_size_bytes <= 0 OR p_file_size_bytes > 10485760 THEN
    RAISE EXCEPTION 'Submission rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_sha256_client IS NULL OR p_sha256_client !~ '^[a-f0-9]{64}$' THEN
    RAISE EXCEPTION 'Submission rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_token FROM public.dispute_portal_tokens
   WHERE token = p_token FOR UPDATE;
  -- Anti-oracle: token invalid / not submit-scoped / revoked / expired all alike.
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

  -- Per-token submission cap (availability ceiling), race-free under the lock.
  SELECT count(*) INTO v_count FROM public.portal_evidence_submissions
   WHERE token_id = v_token.id AND deleted_at IS NULL;
  IF v_count >= v_token.max_submissions THEN
    RAISE EXCEPTION 'Submission rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  v_path := v_token.id::text || '/' || v_id::text || '.' || v_ext;

  INSERT INTO public.portal_evidence_submissions
    (id, organization_id, queue_entry_id, token_id, quarantine_storage_path,
     file_name, mime_type_declared, file_size_bytes_declared, sha256_client,
     submitter_ip, submitter_correlation_id, submitted_at_utc)
  VALUES
    (v_id, v_token.organization_id, v_token.queue_entry_id, v_token.id, v_path,
     p_file_name, p_mime_type, p_file_size_bytes, p_sha256_client,
     p_submitter_ip::inet, p_correlation_id, v_now);

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
      'file_size_bytes_declared', p_file_size_bytes
    ),
    v_now
  );

  submission_id := v_id;
  quarantine_path := v_path;
  RETURN NEXT;
END;
$$;

-- ── 5. register_portal_evidence (service_role) ───────────────────────────────
-- Finalize success path. The edge fn has already re-downloaded the bytes,
-- sniffed magic bytes, and recomputed SHA-256 server-side (the ONLY canonical
-- hash, INV-9). Production path is DERIVED from the submission's sealed fields,
-- never from carrier input. Idempotent: a second call returns the existing
-- attachment instead of re-inserting.
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
  v_sub    public.portal_evidence_submissions;
  v_queue  public.sanction_review_queue;
  v_ext    TEXT;
  v_path   TEXT;
  v_count  INT;
  v_id     UUID;
  v_now    TIMESTAMPTZ := NOW();
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
    -- MISMATCH / REJECTED / EXPIRED / ACCEPTED — cannot finalize.
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

  BEGIN
    INSERT INTO public.dispute_evidence_attachments
      (organization_id, queue_entry_id, storage_path, file_name, mime_type,
       file_size_bytes, sha256_hash, verification_status, hash_verified_at,
       uploaded_by, submission_id, attached_at)
    VALUES
      (v_sub.organization_id, v_sub.queue_entry_id, v_path, v_sub.file_name,
       p_mime_type_detected, p_file_size_bytes_actual, p_sha256_server,
       'VERIFIED', v_now, NULL, v_sub.id, v_now)
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

  INSERT INTO public.sla_audit_ledger_v2
    (organization_id, type, operator_id, set_id, contract_id, plan_version, payload, occurred_at_utc)
  VALUES (
    v_sub.organization_id, 'PORTAL_EVIDENCE_FINALIZED', 'PORTAL',
    v_queue.set_id, v_queue.contract_id::uuid, 0,
    jsonb_build_object(
      'queue_entry_id', v_sub.queue_entry_id,
      'submission_id', v_sub.id,
      'attachment_id', v_id,
      'sha256_server', p_sha256_server
    ),
    v_now
  );

  RETURN v_id;
END;
$$;

-- ── 6. fail_portal_submission (service_role) ─────────────────────────────────
-- Finalize failure path. Records why the submission was rejected without ever
-- creating an attachment. p_kind ∈ HASH_MISMATCH | MIME_MISMATCH | REJECTED.
CREATE OR REPLACE FUNCTION public.fail_portal_submission(
  p_submission_id UUID,
  p_kind          TEXT,
  p_detail        TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_sub        public.portal_evidence_submissions;
  v_queue      public.sanction_review_queue;
  v_new_status TEXT;
  v_type       TEXT;
  v_now        TIMESTAMPTZ := NOW();
BEGIN
  IF p_kind = 'HASH_MISMATCH' THEN
    v_new_status := 'MISMATCH'; v_type := 'PORTAL_EVIDENCE_HASH_MISMATCH';
  ELSIF p_kind = 'MIME_MISMATCH' THEN
    v_new_status := 'MISMATCH'; v_type := 'PORTAL_EVIDENCE_MIME_MISMATCH';
  ELSIF p_kind = 'REJECTED' THEN
    v_new_status := 'REJECTED'; v_type := 'PORTAL_EVIDENCE_REJECTED';
  ELSE
    RAISE EXCEPTION 'Submission rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_sub FROM public.portal_evidence_submissions
   WHERE id = p_submission_id FOR UPDATE;
  IF NOT FOUND OR v_sub.status <> 'QUARANTINE' THEN
    RAISE EXCEPTION 'Submission rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_queue FROM public.sanction_review_queue
   WHERE id = v_sub.queue_entry_id AND organization_id = v_sub.organization_id;

  UPDATE public.portal_evidence_submissions
     SET status = v_new_status, finalized_at_utc = v_now
   WHERE id = v_sub.id;

  INSERT INTO public.sla_audit_ledger_v2
    (organization_id, type, operator_id, set_id, contract_id, plan_version, payload, occurred_at_utc)
  VALUES (
    v_sub.organization_id, v_type, 'PORTAL',
    v_queue.set_id, v_queue.contract_id::uuid, 0,
    jsonb_build_object(
      'queue_entry_id', v_sub.queue_entry_id,
      'submission_id', v_sub.id,
      'detail', p_detail
    ),
    v_now
  );
END;
$$;

-- ── 7. audit_portal_submission (authenticated TENANT_ADMIN/AUDITOR) ──────────
-- Human review of a PENDING_AUDIT submission. ACCEPT keeps the attachment;
-- REJECT soft-deletes the linked attachment (no longer counts as evidence).
CREATE OR REPLACE FUNCTION public.audit_portal_submission(
  p_organization_id UUID,
  p_submission_id   UUID,
  p_decision        TEXT,
  p_audited_by      UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_jwt_org    TEXT;
  v_jwt_role   TEXT;
  v_user       UUID;
  v_sub        public.portal_evidence_submissions;
  v_queue      public.sanction_review_queue;
  v_new_status TEXT;
  v_type       TEXT;
  v_now        TIMESTAMPTZ := NOW();
BEGIN
  v_jwt_org := auth.jwt() -> 'app_metadata' ->> 'org_id';
  IF v_jwt_org IS NULL OR v_jwt_org::uuid <> p_organization_id THEN
    RAISE EXCEPTION 'Audit rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  v_jwt_role := auth.jwt() -> 'app_metadata' ->> 'role';
  IF v_jwt_role IS NULL OR v_jwt_role NOT IN ('TENANT_ADMIN','AUDITOR') THEN
    RAISE EXCEPTION 'Audit rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  v_user := (auth.jwt() ->> 'sub')::uuid;
  IF v_user IS NULL OR v_user <> p_audited_by THEN
    RAISE EXCEPTION 'Audit rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF p_decision = 'accept' THEN
    v_new_status := 'ACCEPTED'; v_type := 'PORTAL_EVIDENCE_AUDITOR_ACCEPTED';
  ELSIF p_decision = 'reject' THEN
    v_new_status := 'REJECTED'; v_type := 'PORTAL_EVIDENCE_AUDITOR_REJECTED';
  ELSE
    RAISE EXCEPTION 'Audit rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended(p_organization_id::text || '/sub/' || p_submission_id::text, 0)
  );

  SELECT * INTO v_sub FROM public.portal_evidence_submissions
   WHERE id = p_submission_id AND organization_id = p_organization_id
   FOR UPDATE;
  IF NOT FOUND OR v_sub.status <> 'PENDING_AUDIT' THEN
    RAISE EXCEPTION 'Audit rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_queue FROM public.sanction_review_queue
   WHERE id = v_sub.queue_entry_id AND organization_id = p_organization_id;

  UPDATE public.portal_evidence_submissions
     SET status = v_new_status, audited_by = v_user, audited_at = v_now
   WHERE id = v_sub.id;

  -- Reject retires the attachment from the evidence set (soft-delete).
  IF v_new_status = 'REJECTED' THEN
    UPDATE public.dispute_evidence_attachments
       SET deleted_at = v_now
     WHERE submission_id = v_sub.id AND deleted_at IS NULL;
  END IF;

  INSERT INTO public.sla_audit_ledger_v2
    (organization_id, type, operator_id, set_id, contract_id, plan_version, payload, occurred_at_utc)
  VALUES (
    p_organization_id, v_type, v_user::text,
    v_queue.set_id, v_queue.contract_id::uuid, 0,
    jsonb_build_object(
      'queue_entry_id', v_sub.queue_entry_id,
      'submission_id', v_sub.id,
      'audited_by', v_user
    ),
    v_now
  );
END;
$$;

-- ── 8. acknowledge_via_portal (anon + authenticated) ─────────────────────────
-- Carrier "De Acordo" through the tokenized portal. Hash-bound: the carrier may
-- only acknowledge the snapshot the system provably served — the snapshot_hash
-- recorded in the DISPUTE_PORTAL_TOKEN_ACCESSED ledger fact for this token.
-- Idempotent per token; atomic (ack row + status → acknowledged + ledger fact).
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

  -- De Acordo is only meaningful once the sanction is applied.
  IF v_queue.status <> 'applied' THEN
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

-- ── 9. acknowledge_sanction_internal (authenticated TENANT_ADMIN) ────────────
-- Off-band acceptance (documented email/phone). No hash. INTERNAL_RECORD.
CREATE OR REPLACE FUNCTION public.acknowledge_sanction_internal(
  p_organization_id UUID,
  p_queue_entry_id  UUID,
  p_acknowledged_by UUID,
  p_notes           TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_jwt_org  TEXT;
  v_jwt_role TEXT;
  v_user     UUID;
  v_queue    public.sanction_review_queue;
  v_ack      UUID;
  v_now      TIMESTAMPTZ := NOW();
BEGIN
  v_jwt_org := auth.jwt() -> 'app_metadata' ->> 'org_id';
  IF v_jwt_org IS NULL OR v_jwt_org::uuid <> p_organization_id THEN
    RAISE EXCEPTION 'Acknowledgement rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  v_jwt_role := auth.jwt() -> 'app_metadata' ->> 'role';
  IF v_jwt_role IS NULL OR v_jwt_role <> 'TENANT_ADMIN' THEN
    RAISE EXCEPTION 'Acknowledgement rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  v_user := (auth.jwt() ->> 'sub')::uuid;
  IF v_user IS NULL OR v_user <> p_acknowledged_by THEN
    RAISE EXCEPTION 'Acknowledgement rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended(p_organization_id::text || '/' || p_queue_entry_id::text, 0)
  );

  SELECT * INTO v_queue FROM public.sanction_review_queue
   WHERE id = p_queue_entry_id AND organization_id = p_organization_id
   FOR UPDATE;
  IF NOT FOUND OR v_queue.status <> 'applied' THEN
    RAISE EXCEPTION 'Acknowledgement rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  INSERT INTO public.sanction_acknowledgements
    (organization_id, queue_entry_id, acknowledgement_method,
     acknowledged_by_user_id, notes, acknowledged_at_utc)
  VALUES
    (p_organization_id, p_queue_entry_id, 'INTERNAL_RECORD',
     v_user, p_notes, v_now)
  RETURNING id INTO v_ack;

  UPDATE public.sanction_review_queue
     SET status = 'acknowledged'
   WHERE id = p_queue_entry_id AND organization_id = p_organization_id;

  INSERT INTO public.sla_audit_ledger_v2
    (organization_id, type, operator_id, set_id, contract_id, plan_version, payload, occurred_at_utc)
  VALUES (
    p_organization_id, 'SANCTION_ACKNOWLEDGED', v_user::text,
    v_queue.set_id, v_queue.contract_id::uuid, 0,
    jsonb_build_object(
      'queue_entry_id', p_queue_entry_id,
      'acknowledgement_id', v_ack,
      'method', 'INTERNAL_RECORD',
      'acknowledged_by', v_user
    ),
    v_now
  );

  RETURN v_ack;
END;
$$;

-- ── 10. Grants (INV-DATA-API-GRANT; re-grant explicit — REVOKE FROM PUBLIC ───
--        silently strips service_role/authenticated) ────────────────────────
REVOKE ALL ON FUNCTION public.create_portal_submission(UUID,TEXT,TEXT,BIGINT,TEXT,TEXT,TEXT)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_portal_submission(UUID,TEXT,TEXT,BIGINT,TEXT,TEXT,TEXT)
  TO service_role;

REVOKE ALL ON FUNCTION public.register_portal_evidence(UUID,TEXT,TEXT,BIGINT)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.register_portal_evidence(UUID,TEXT,TEXT,BIGINT)
  TO service_role;

REVOKE ALL ON FUNCTION public.fail_portal_submission(UUID,TEXT,TEXT)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fail_portal_submission(UUID,TEXT,TEXT)
  TO service_role;

REVOKE ALL ON FUNCTION public.audit_portal_submission(UUID,UUID,TEXT,UUID)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.audit_portal_submission(UUID,UUID,TEXT,UUID)
  TO authenticated;

REVOKE ALL ON FUNCTION public.acknowledge_via_portal(UUID,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.acknowledge_via_portal(UUID,TEXT)
  TO anon, authenticated;

REVOKE ALL ON FUNCTION public.acknowledge_sanction_internal(UUID,UUID,UUID,TEXT)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.acknowledge_sanction_internal(UUID,UUID,UUID,TEXT)
  TO authenticated;

RESET client_min_messages;
