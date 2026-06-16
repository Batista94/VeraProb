-- =============================================================================
-- Migration: portal_justification_seal — Dispute Portal Refactor (Pacote 1)
-- Purpose:   Makes the carrier's written justification a first-class, sealed part
--            of every portal counter-evidence submission, and adds the
--            "anexo opcional" (file-optional) path so a carrier can contest with
--            testimony alone.
--
--            The justification is testimony — it carries the same legal weight as
--            the file (QA VETO: never HTML-encode at ingest; store raw validated
--            bytes, escape only at render/export). It is therefore:
--              • sealed-at-ingest (immutable, INV-3) on portal_evidence_submissions
--              • bound to the file via a combined seal
--                sha256_combined_seal = sha256(sha256_server || ':' || justification)
--                stored on dispute_evidence_attachments and sealed (INV-9).
--
-- File-optional design decision (anexo opcional):
--   portal_evidence_submissions requires file_name / mime_type_declared /
--   file_size_bytes_declared / sha256_client to be NOT NULL with format CHECKs.
--   Forcing NULLs (or fake constants) into those columns to record a
--   justification-only contest would either fail the constraints or corrupt the
--   forensic record (a fabricated file row). Instead we record the file-optional
--   contest in a NEW minimal append-only table, portal_justification_submissions
--   (org-scoped, deny-all RLS, service_role-only, immutability trigger), which
--   surfaces to the auditor queue alongside file submissions, plus a ledger fact
--   PORTAL_JUSTIFICATION_SUBMITTED. No file table is polluted; the chain of
--   custody for testimony-only contests is its own provable artifact.
--
-- Justification validity (defense-in-depth; mirrored in the edge fn):
--   NULL allowed at table level ONLY for legacy rows (existing rows have no
--   justification; backfilling fake text would corrupt the forensic record).
--   Mandatory-ness for NEW submissions is enforced in the RPCs. Non-null values
--   must be 10..4000 chars (char_length, NOT octet_length — Unicode-safe) and
--   contain no C0/C1 control chars except TAB/LF/CR.
--
-- Council: Architect ✅ · Senior ✅ · QA-Security ✅ · Business ✅ · Lead ✅
-- Invariants: INV-1, INV-2, INV-3, INV-6, INV-9, INV-18, INV-22, INV-26,
--             INV-DATA-API-GRANT.
-- Depends on: 20260817000002 (submissions), 20260817000005 (rpcs/ledger),
--             20260813000001 (dea), 20260814000002/20260817000001 (tokens).
-- =============================================================================

SET client_min_messages TO 'WARNING';

-- ── 1. justification_text on portal_evidence_submissions (sealed testimony) ───
-- NULLABLE at table level (legacy rows). The validity CHECK constrains only
-- non-null values; added NOT VALID then VALIDATEd (zero-downtime — existing
-- NULL rows trivially conform). char_length (not octet_length) for Unicode;
-- reject C0/C1 control chars except TAB (\x09) / LF (\x0A) / CR (\x0D).

ALTER TABLE public.portal_evidence_submissions
  ADD COLUMN IF NOT EXISTS justification_text TEXT;

COMMENT ON COLUMN public.portal_evidence_submissions.justification_text IS
  'Carrier testimony (raw, validated). Sealed at ingest (INV-3/INV-9). NULL only for legacy rows; mandatory for new submissions (enforced in RPC). Escape at render/export, never at ingest.';

ALTER TABLE public.portal_evidence_submissions
  ADD CONSTRAINT chk_pes_justification_valid CHECK (
    justification_text IS NULL OR (
      char_length(justification_text) BETWEEN 10 AND 4000
      AND justification_text !~ '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'
    )
  ) NOT VALID;
ALTER TABLE public.portal_evidence_submissions
  VALIDATE CONSTRAINT chk_pes_justification_valid;

-- ── 2. sha256_combined_seal on dispute_evidence_attachments (INV-9) ───────────
-- Binds the file's server hash to the testimony: sha256(sha256_server || ':' ||
-- justification). NULLABLE (legacy + file-only direct uploads have no portal
-- testimony). Format CHECK on non-null values only (zero-downtime).

ALTER TABLE public.dispute_evidence_attachments
  ADD COLUMN IF NOT EXISTS sha256_combined_seal TEXT;

COMMENT ON COLUMN public.dispute_evidence_attachments.sha256_combined_seal IS
  'Combined seal sha256(sha256_hash || '':'' || justification_text) binding the file to the carrier testimony (INV-9). NULL for non-portal / legacy attachments. Sealed (INV-3).';

ALTER TABLE public.dispute_evidence_attachments
  ADD CONSTRAINT chk_dea_combined_seal_format CHECK (
    sha256_combined_seal IS NULL OR sha256_combined_seal ~ '^[a-f0-9]{64}$'
  ) NOT VALID;
ALTER TABLE public.dispute_evidence_attachments
  VALIDATE CONSTRAINT chk_dea_combined_seal_format;

-- ── 3. portal_justification_submissions (file-optional contest record) ────────
-- Minimal append-only artifact for a testimony-only contest. Mirrors the
-- portal_evidence_submissions security posture: deny-all RLS, service_role-only
-- (via SECURITY DEFINER RPC), immutability trigger, no hard DELETE.

CREATE TABLE IF NOT EXISTS public.portal_justification_submissions (
  id                       UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id          UUID        NOT NULL REFERENCES public.organizations(id),
  queue_entry_id           UUID        NOT NULL REFERENCES public.sanction_review_queue(id),
  token_id                 UUID        NOT NULL REFERENCES public.dispute_portal_tokens(id),

  -- Sealed-at-ingest testimony (same validity rule as the file path).
  justification_text       TEXT        NOT NULL
    CONSTRAINT chk_pjs_justification_valid CHECK (
      char_length(justification_text) BETWEEN 10 AND 4000
      AND justification_text !~ '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'
    ),
  -- Seal of the testimony alone (no file): sha256(justification).
  sha256_justification_seal TEXT       NOT NULL
    CONSTRAINT chk_pjs_seal_format CHECK (sha256_justification_seal ~ '^[a-f0-9]{64}$'),

  -- Auditor review state. A testimony-only contest is born ready for review
  -- (no quarantine/finalize step — there are no bytes to re-hash).
  status                   TEXT        NOT NULL DEFAULT 'PENDING_AUDIT'
    CONSTRAINT chk_pjs_status CHECK (status IN ('PENDING_AUDIT','ACCEPTED','REJECTED')),

  -- Submitter provenance (best-effort, untrusted).
  submitter_ip             INET,
  submitter_correlation_id TEXT,
  submitted_at_utc         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  submitted_via            TEXT        NOT NULL DEFAULT 'PORTAL'
    CONSTRAINT chk_pjs_submitted_via CHECK (submitted_via IN ('PORTAL')),

  deleted_at               TIMESTAMPTZ
);

COMMENT ON TABLE public.portal_justification_submissions IS
  'deny-all: append-only record of file-optional (testimony-only) portal contests. service_role only (via SECURITY DEFINER RPC submit_portal_justification_only). Surfaces to the auditor queue (INV-22).';

CREATE INDEX IF NOT EXISTS idx_pjs_org_queue
  ON public.portal_justification_submissions (organization_id, queue_entry_id)
  WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_pjs_token
  ON public.portal_justification_submissions (token_id)
  WHERE deleted_at IS NULL;

-- Immutability trigger: every column sealed at ingest; soft-delete is terminal.
CREATE OR REPLACE FUNCTION public.prevent_pjs_immutable_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  -- Sealed-at-ingest fields can never change (status + deleted_at are mutable).
  IF NEW.organization_id           IS DISTINCT FROM OLD.organization_id           OR
     NEW.queue_entry_id            IS DISTINCT FROM OLD.queue_entry_id            OR
     NEW.token_id                  IS DISTINCT FROM OLD.token_id                  OR
     NEW.justification_text        IS DISTINCT FROM OLD.justification_text        OR
     NEW.sha256_justification_seal IS DISTINCT FROM OLD.sha256_justification_seal OR
     NEW.submitter_ip              IS DISTINCT FROM OLD.submitter_ip              OR
     NEW.submitter_correlation_id  IS DISTINCT FROM OLD.submitter_correlation_id OR
     NEW.submitted_at_utc          IS DISTINCT FROM OLD.submitted_at_utc          OR
     NEW.submitted_via             IS DISTINCT FROM OLD.submitted_via
  THEN
    RAISE EXCEPTION
      'portal_justification_submissions: immutable field mutation (INV-3/INV-9). id: %', OLD.id
    USING ERRCODE = 'restrict_violation';
  END IF;

  -- Status monotonicity: PENDING_AUDIT → ACCEPTED/REJECTED only (terminal once decided).
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    IF NOT (OLD.status = 'PENDING_AUDIT' AND NEW.status IN ('ACCEPTED','REJECTED')) THEN
      RAISE EXCEPTION
        'portal_justification_submissions: illegal status transition % → % (INV-3). id: %',
        OLD.status, NEW.status, OLD.id
      USING ERRCODE = 'restrict_violation';
    END IF;
  END IF;

  IF OLD.deleted_at IS NOT NULL AND NEW.deleted_at IS NULL THEN
    RAISE EXCEPTION
      'portal_justification_submissions: cannot resurrect soft-deleted record (INV-3). id: %', OLD.id
    USING ERRCODE = 'restrict_violation';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_pjs_no_immutable_update ON public.portal_justification_submissions;
CREATE TRIGGER trg_pjs_no_immutable_update
  BEFORE UPDATE ON public.portal_justification_submissions
  FOR EACH ROW EXECUTE FUNCTION public.prevent_pjs_immutable_mutation();

CREATE OR REPLACE FUNCTION public.prevent_pjs_delete()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION
    'portal_justification_submissions is append-only. Use soft-delete (deleted_at). id: %', OLD.id
  USING ERRCODE = 'restrict_violation';
END;
$$;
DROP TRIGGER IF EXISTS trg_pjs_no_delete ON public.portal_justification_submissions;
CREATE TRIGGER trg_pjs_no_delete
  BEFORE DELETE ON public.portal_justification_submissions
  FOR EACH ROW EXECUTE FUNCTION public.prevent_pjs_delete();

-- RLS (INV-2, INV-22): deny-all — service_role only (via SECURITY DEFINER RPC).
ALTER TABLE public.portal_justification_submissions ENABLE ROW LEVEL SECURITY;
-- No SELECT/INSERT/UPDATE/DELETE policies for anon or authenticated.

-- Data API grants (INV-DATA-API-GRANT). REVOKE raw privileges legacy ALTER
-- DEFAULT PRIVILEGES may leak so the SECURITY DEFINER path is provably the only one.
REVOKE ALL ON TABLE public.portal_justification_submissions FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.portal_justification_submissions TO service_role;

-- ── 4. Re-derive prevent_pes_immutable_mutation (seal justification_text) ─────
-- Full body copied from 20260817000002; justification_text added to the
-- sealed-at-ingest immutable block.
CREATE OR REPLACE FUNCTION public.prevent_pes_immutable_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  -- Sealed-at-ingest fields can never change.
  IF NEW.organization_id          IS DISTINCT FROM OLD.organization_id          OR
     NEW.queue_entry_id           IS DISTINCT FROM OLD.queue_entry_id           OR
     NEW.token_id                 IS DISTINCT FROM OLD.token_id                 OR
     NEW.quarantine_storage_path  IS DISTINCT FROM OLD.quarantine_storage_path  OR
     NEW.file_name                IS DISTINCT FROM OLD.file_name                OR
     NEW.mime_type_declared       IS DISTINCT FROM OLD.mime_type_declared       OR
     NEW.file_size_bytes_declared IS DISTINCT FROM OLD.file_size_bytes_declared OR
     NEW.sha256_client            IS DISTINCT FROM OLD.sha256_client            OR
     NEW.justification_text       IS DISTINCT FROM OLD.justification_text       OR
     NEW.submitter_ip             IS DISTINCT FROM OLD.submitter_ip             OR
     NEW.submitter_correlation_id IS DISTINCT FROM OLD.submitter_correlation_id OR
     NEW.submitted_at_utc         IS DISTINCT FROM OLD.submitted_at_utc         OR
     NEW.submitted_via            IS DISTINCT FROM OLD.submitted_via
  THEN
    RAISE EXCEPTION
      'portal_evidence_submissions: immutable field mutation (INV-3/INV-9). id: %', OLD.id
    USING ERRCODE = 'restrict_violation';
  END IF;

  -- Seal-once fields: NULL → value exactly once, then frozen.
  IF (OLD.production_storage_path IS NOT NULL AND
      NEW.production_storage_path IS DISTINCT FROM OLD.production_storage_path) OR
     (OLD.mime_type_detected IS NOT NULL AND
      NEW.mime_type_detected IS DISTINCT FROM OLD.mime_type_detected) OR
     (OLD.file_size_bytes_actual IS NOT NULL AND
      NEW.file_size_bytes_actual IS DISTINCT FROM OLD.file_size_bytes_actual) OR
     (OLD.sha256_server IS NOT NULL AND
      NEW.sha256_server IS DISTINCT FROM OLD.sha256_server) OR
     (OLD.finalized_at_utc IS NOT NULL AND
      NEW.finalized_at_utc IS DISTINCT FROM OLD.finalized_at_utc) OR
     (OLD.audited_by IS NOT NULL AND
      NEW.audited_by IS DISTINCT FROM OLD.audited_by) OR
     (OLD.audited_at IS NOT NULL AND
      NEW.audited_at IS DISTINCT FROM OLD.audited_at)
  THEN
    RAISE EXCEPTION
      'portal_evidence_submissions: seal-once field re-mutation (INV-9). id: %', OLD.id
    USING ERRCODE = 'restrict_violation';
  END IF;

  -- Status monotonicity: only the lifecycle edges below are legal.
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    IF NOT (
      (OLD.status = 'QUARANTINE'    AND NEW.status IN ('PENDING_AUDIT','MISMATCH','REJECTED','EXPIRED')) OR
      (OLD.status = 'PENDING_AUDIT' AND NEW.status IN ('ACCEPTED','REJECTED'))
    ) THEN
      RAISE EXCEPTION
        'portal_evidence_submissions: illegal status transition % → % (INV-3). id: %',
        OLD.status, NEW.status, OLD.id
      USING ERRCODE = 'restrict_violation';
    END IF;
  END IF;

  -- Soft-delete is terminal: never resurrect a deleted submission.
  IF OLD.deleted_at IS NOT NULL AND NEW.deleted_at IS NULL THEN
    RAISE EXCEPTION
      'portal_evidence_submissions: cannot resurrect soft-deleted submission (INV-3). id: %', OLD.id
    USING ERRCODE = 'restrict_violation';
  END IF;

  RETURN NEW;
END;
$$;

-- ── 5. Re-derive prevent_dea_immutable_mutation (seal sha256_combined_seal) ───
-- Full body copied from 20260817000005; sha256_combined_seal added to the
-- sealed field list.
CREATE OR REPLACE FUNCTION public.prevent_dea_immutable_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.organization_id      IS DISTINCT FROM OLD.organization_id      OR
     NEW.queue_entry_id       IS DISTINCT FROM OLD.queue_entry_id       OR
     NEW.storage_path         IS DISTINCT FROM OLD.storage_path         OR
     NEW.sha256_hash          IS DISTINCT FROM OLD.sha256_hash          OR
     NEW.file_name            IS DISTINCT FROM OLD.file_name            OR
     NEW.mime_type            IS DISTINCT FROM OLD.mime_type            OR
     NEW.file_size_bytes      IS DISTINCT FROM OLD.file_size_bytes      OR
     NEW.uploaded_by          IS DISTINCT FROM OLD.uploaded_by          OR
     NEW.submission_id        IS DISTINCT FROM OLD.submission_id        OR
     NEW.sha256_combined_seal IS DISTINCT FROM OLD.sha256_combined_seal OR
     NEW.attached_at          IS DISTINCT FROM OLD.attached_at
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

-- ── 6. Widen chk_ledger_type (v6 swap → canonical name preserved) ────────────
-- Adds PORTAL_JUSTIFICATION_SUBMITTED. NOT VALID → VALIDATE → DROP old → RENAME.
ALTER TABLE public.sla_audit_ledger_v2
  ADD CONSTRAINT chk_ledger_type_v6 CHECK (type IN (
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
    'SANCTION_ACKNOWLEDGED',
    -- Dispute Portal Refactor (Pacote 1) — testimony-only contest
    'PORTAL_JUSTIFICATION_SUBMITTED'
  )) NOT VALID; -- INV-DB: zero-downtime-verified (superset; existing rows conform)
ALTER TABLE public.sla_audit_ledger_v2 VALIDATE CONSTRAINT chk_ledger_type_v6;
ALTER TABLE public.sla_audit_ledger_v2 DROP CONSTRAINT IF EXISTS chk_ledger_type; -- INV-DB: zero-downtime-verified (CHECK swap)
ALTER TABLE public.sla_audit_ledger_v2 RENAME CONSTRAINT chk_ledger_type_v6 TO chk_ledger_type;

-- ── 7. create_portal_submission — now justification-requiring ────────────────
-- Signature change: add required p_justification (logical position: after the
-- file metadata, before submitter provenance). DROP the old 7-arg overload and
-- CREATE the new 8-arg one so PostgREST resolves the new shape unambiguously.
-- Validation raises the SAME opaque 'Submission rejected.' / insufficient_privilege
-- as every other check (anti-oracle, INV-26 — never leak which check failed).
DROP FUNCTION IF EXISTS public.create_portal_submission(UUID,TEXT,TEXT,BIGINT,TEXT,TEXT,TEXT);

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
  v_token  public.dispute_portal_tokens;
  v_queue  public.sanction_review_queue;
  v_ext    TEXT;
  v_count  INT;
  v_id     UUID := gen_random_uuid();
  v_path   TEXT;
  v_now    TIMESTAMPTZ := NOW();
BEGIN
  -- Timing normalization: lock both FOUND and NOT-FOUND paths.
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
  -- Justification is mandatory (testimony). Same opaque error (anti-oracle).
  -- trim() rejects all-whitespace input (char_length alone would admit "          ").
  IF p_justification IS NULL
     OR char_length(p_justification) > 4000
     OR char_length(trim(p_justification)) < 10
     OR p_justification ~ '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'
  THEN
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

-- ── 8. register_portal_evidence — store combined seal (testimony + file) ──────
-- Signature unchanged (justification already persisted Phase 1). Reads
-- v_sub.justification_text and computes the combined seal server-side.
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

  -- Combined seal binds the server hash to the carrier testimony (INV-9).
  -- justification_text is NOT NULL for any submission minted by the new RPC.
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

-- ── 9. submit_portal_justification_only (service_role) ───────────────────────
-- File-optional (anexo opcional) contest. Same token idiom as
-- create_portal_submission (submit-scope, not revoked/expired, queue disputed,
-- per-token cap under advisory lock+count). Records the testimony in
-- portal_justification_submissions and logs PORTAL_JUSTIFICATION_SUBMITTED. The
-- per-token cap counts BOTH file submissions and justification-only submissions
-- so a single token cannot be used to flood the auditor queue.
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
  v_token  public.dispute_portal_tokens;
  v_queue  public.sanction_review_queue;
  v_count  INT;
  v_id     UUID;
  v_seal   TEXT;
  v_now    TIMESTAMPTZ := NOW();
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

-- ── 10. list_portal_justification_submissions (auditor read path) ────────────
-- Safe SELECT over the deny-all portal_justification_submissions table for the
-- auditor queue. Companion to list_portal_submissions (M6) — a SEPARATE RPC
-- (not a widened return shape) to avoid PostgREST signature drift on the
-- existing function. Org-scoped, TENANT_ADMIN/AUDITOR only (INV-22, INV-26).
CREATE OR REPLACE FUNCTION public.list_portal_justification_submissions(
  p_organization_id UUID,
  p_queue_entry_id  UUID
)
RETURNS TABLE (
  justification_submission_id UUID,
  justification_text          TEXT,
  sha256_justification_seal   TEXT,
  status                      TEXT,
  submitted_at_utc            TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_jwt_org  TEXT;
  v_jwt_role TEXT;
BEGIN
  v_jwt_org := auth.jwt() -> 'app_metadata' ->> 'org_id';
  IF v_jwt_org IS NULL OR v_jwt_org::uuid <> p_organization_id THEN
    RAISE EXCEPTION 'Listing rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  v_jwt_role := auth.jwt() -> 'app_metadata' ->> 'role';
  IF v_jwt_role IS NULL OR v_jwt_role NOT IN ('TENANT_ADMIN', 'AUDITOR') THEN
    RAISE EXCEPTION 'Listing rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  RETURN QUERY
    SELECT
      pjs.id,
      pjs.justification_text,
      pjs.sha256_justification_seal,
      pjs.status,
      pjs.submitted_at_utc
    FROM public.portal_justification_submissions pjs
   WHERE pjs.organization_id = p_organization_id
     AND pjs.queue_entry_id = p_queue_entry_id
     AND pjs.deleted_at IS NULL
   ORDER BY pjs.submitted_at_utc;
END;
$$;

-- ── 11. Grants (INV-DATA-API-GRANT) ──────────────────────────────────────────
-- New create_portal_submission arity (8 args) — re-grant explicit (REVOKE FROM
-- PUBLIC silently strips service_role/authenticated).
REVOKE ALL ON FUNCTION public.create_portal_submission(UUID,TEXT,TEXT,BIGINT,TEXT,TEXT,TEXT,TEXT)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_portal_submission(UUID,TEXT,TEXT,BIGINT,TEXT,TEXT,TEXT,TEXT)
  TO service_role;

-- register_portal_evidence signature unchanged — re-assert grant defensively.
REVOKE ALL ON FUNCTION public.register_portal_evidence(UUID,TEXT,TEXT,BIGINT)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.register_portal_evidence(UUID,TEXT,TEXT,BIGINT)
  TO service_role;

REVOKE ALL ON FUNCTION public.submit_portal_justification_only(UUID,TEXT)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.submit_portal_justification_only(UUID,TEXT)
  TO service_role;

REVOKE ALL ON FUNCTION public.list_portal_justification_submissions(UUID,UUID)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.list_portal_justification_submissions(UUID,UUID)
  TO authenticated;

RESET client_min_messages;
