-- =============================================================================
-- Migration: portal_evidence_submissions — Sprint A (Portal Submissão) M2
-- Purpose:   Quarantine ledger for carrier-submitted counter-evidence. A row is
--            born in QUARANTINE when the carrier requests a signed upload URL
--            (portal-submit-request), and is promoted only after finalize
--            re-downloads the bytes, sniffs magic bytes, and recomputes SHA-256
--            server-side (portal-finalize-upload). Nothing here is trusted: the
--            carrier-declared mime/size/hash are recorded but NEVER canonical.
--
-- Lifecycle: QUARANTINE ─┬─▶ PENDING_AUDIT ─┬─▶ ACCEPTED   (auditor accepts)
--                        │                  └─▶ REJECTED   (auditor rejects)
--                        ├─▶ MISMATCH   (server hash/mime ≠ declared — sealed)
--                        ├─▶ REJECTED   (finalize-time rejection)
--                        └─▶ EXPIRED    (orphan sweep, Phase 10.9)
--            ACCEPTED / REJECTED / MISMATCH / EXPIRED are terminal.
--
-- Pattern:   Mirrors dispute_evidence_attachments (sealed fields, append-only,
--            soft-delete) + dispute_portal_tokens (deny-all RLS, service_role).
--            Sealed-at-ingest fields are immutable; finalize/audit fields are
--            seal-once (NULL → value, then frozen) so finalize is replay-safe.
--
-- Council: Architect ✅ · Senior ✅ · QA-Security ✅ · Business ✅ · Lead ✅
-- Invariants: INV-1, INV-2, INV-3, INV-6, INV-9, INV-18 (zero-trust), INV-22,
--             INV-26, INV-DATA-API-GRANT.
-- Depends on: 20260817000001 (token_scope), 20260814000002 (token table),
--             20260406000001 (sanction_review_queue).
-- =============================================================================

SET client_min_messages TO 'WARNING';

-- ── 1. Table ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.portal_evidence_submissions (
  id                       UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id          UUID        NOT NULL REFERENCES public.organizations(id),
  queue_entry_id           UUID        NOT NULL REFERENCES public.sanction_review_queue(id),
  token_id                 UUID        NOT NULL REFERENCES public.dispute_portal_tokens(id),

  -- ── Sealed at ingest (portal-submit-request) — never change ────────────────
  -- Quarantine path carries NO org_id (anti-inference): {token_id}/{uuid}.ext.
  quarantine_storage_path  TEXT        NOT NULL,
  file_name                TEXT        NOT NULL,

  -- Carrier-DECLARED metadata. Zero-trust (INV-18): recorded, never canonical.
  mime_type_declared       TEXT        NOT NULL
    CONSTRAINT chk_pes_mime_declared CHECK (
      mime_type_declared IN ('image/jpeg','image/png','application/pdf',
                             'image/heic','image/heif','image/webp')
    ),
  file_size_bytes_declared BIGINT      NOT NULL
    CONSTRAINT chk_pes_size_declared CHECK (
      file_size_bytes_declared > 0 AND file_size_bytes_declared <= 10485760
    ),
  sha256_client            TEXT        NOT NULL
    CONSTRAINT chk_pes_sha_client CHECK (sha256_client ~ '^[a-f0-9]{64}$'),

  -- Submitter provenance (best-effort, untrusted).
  submitter_ip             INET,
  submitter_correlation_id TEXT,
  submitted_at_utc         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  submitted_via            TEXT        NOT NULL DEFAULT 'PORTAL'
    CONSTRAINT chk_pes_submitted_via CHECK (submitted_via IN ('PORTAL')),

  -- ── Seal-once (portal-finalize-upload) — NULL → value, then frozen ─────────
  production_storage_path  TEXT,
  mime_type_detected       TEXT,
  file_size_bytes_actual   BIGINT
    CONSTRAINT chk_pes_size_actual CHECK (
      file_size_bytes_actual IS NULL
      OR (file_size_bytes_actual > 0 AND file_size_bytes_actual <= 10485760)
    ),
  -- Server-recomputed canonical hash (INV-9). The ONLY hash that may seal an
  -- attachment downstream; sha256_client is advisory.
  sha256_server            TEXT
    CONSTRAINT chk_pes_sha_server CHECK (
      sha256_server IS NULL OR sha256_server ~ '^[a-f0-9]{64}$'
    ),
  finalized_at_utc         TIMESTAMPTZ,

  -- ── Lifecycle status (monotonic, see trigger) ─────────────────────────────
  status                   TEXT        NOT NULL DEFAULT 'QUARANTINE'
    CONSTRAINT chk_pes_status CHECK (
      status IN ('QUARANTINE','PENDING_AUDIT','MISMATCH','REJECTED','EXPIRED','ACCEPTED')
    ),

  -- ── Auditor decision (seal-once) ───────────────────────────────────────────
  audited_by               UUID,
  audited_at               TIMESTAMPTZ,

  -- ── Soft-delete (INV-DB: no hard DELETE) ──────────────────────────────────
  deleted_at               TIMESTAMPTZ,

  -- One submission row per quarantine object (anti-replay of the same upload).
  CONSTRAINT uq_pes_token_path UNIQUE (token_id, quarantine_storage_path)
);

COMMENT ON TABLE public.portal_evidence_submissions IS
  'deny-all: Quarantine ledger for carrier counter-evidence. service_role only (via SECURITY DEFINER RPCs / edge fns). Zero-trust until finalize re-hashes server-side (INV-9, INV-18).';
COMMENT ON COLUMN public.portal_evidence_submissions.sha256_client IS
  'Carrier-declared SHA-256. Advisory only — NEVER the canonical seal (INV-9). Compared against sha256_server at finalize.';
COMMENT ON COLUMN public.portal_evidence_submissions.sha256_server IS
  'Server-recomputed canonical SHA-256 (INV-9). Set once at finalize, then sealed.';

-- ── Indexes ───────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_pes_org_queue
  ON public.portal_evidence_submissions (organization_id, queue_entry_id)
  WHERE deleted_at IS NULL;

-- Auditor work queue: live submissions awaiting human review, per tenant.
CREATE INDEX IF NOT EXISTS idx_pes_pending_audit
  ON public.portal_evidence_submissions (organization_id, queue_entry_id)
  WHERE status = 'PENDING_AUDIT' AND deleted_at IS NULL;

-- Per-token submission counting (cap enforcement under advisory lock).
CREATE INDEX IF NOT EXISTS idx_pes_token
  ON public.portal_evidence_submissions (token_id)
  WHERE deleted_at IS NULL;

-- ── Immutability + status-monotonicity trigger (INV-3, INV-9) ────────────────
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
     NEW.submitter_ip             IS DISTINCT FROM OLD.submitter_ip             OR
     NEW.submitter_correlation_id IS DISTINCT FROM OLD.submitter_correlation_id OR
     NEW.submitted_at_utc         IS DISTINCT FROM OLD.submitted_at_utc         OR
     NEW.submitted_via            IS DISTINCT FROM OLD.submitted_via
  THEN
    RAISE EXCEPTION
      'portal_evidence_submissions: immutable field mutation (INV-3/INV-9). id: %', OLD.id
    USING ERRCODE = 'restrict_violation';
  END IF;

  -- Seal-once fields: NULL → value exactly once, then frozen. Makes finalize and
  -- the auditor decision replay-safe (no silent overwrite of the canonical hash).
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

  -- Status monotonicity: only the lifecycle edges below are legal. Terminal
  -- states (ACCEPTED/REJECTED/MISMATCH/EXPIRED) have no outgoing edge.
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

DROP TRIGGER IF EXISTS trg_pes_no_immutable_update ON public.portal_evidence_submissions;
CREATE TRIGGER trg_pes_no_immutable_update
  BEFORE UPDATE ON public.portal_evidence_submissions
  FOR EACH ROW EXECUTE FUNCTION public.prevent_pes_immutable_mutation();

-- ── Block DELETE (append-only, INV-3) ────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.prevent_pes_delete()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION
    'portal_evidence_submissions is append-only. Use soft-delete (deleted_at). id: %', OLD.id
  USING ERRCODE = 'restrict_violation';
END;
$$;
DROP TRIGGER IF EXISTS trg_pes_no_delete ON public.portal_evidence_submissions;
CREATE TRIGGER trg_pes_no_delete
  BEFORE DELETE ON public.portal_evidence_submissions
  FOR EACH ROW EXECUTE FUNCTION public.prevent_pes_delete();

-- ── RLS (INV-2, INV-22): deny-all — service_role only ────────────────────────
-- The quarantine table holds untrusted carrier paths/bytes. No client may read
-- it directly (quarantine paths must not leak); auditor reads go through a
-- SECURITY DEFINER read model that exposes only safe columns. service_role
-- (edge fns / SECURITY DEFINER RPCs) is the sole writer.

ALTER TABLE public.portal_evidence_submissions ENABLE ROW LEVEL SECURITY;

-- No SELECT/INSERT/UPDATE/DELETE policies for anon or authenticated.

-- ── Data API Grants (INV-DATA-API-GRANT) ─────────────────────────────────────
-- Defense-in-depth: REVOKE the raw privileges legacy ALTER DEFAULT PRIVILEGES
-- may leak to authenticated/anon, so the SECURITY DEFINER path is provably the
-- only one (cf. 20260811000000_harden_client_role_grants).
REVOKE ALL ON TABLE public.portal_evidence_submissions FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.portal_evidence_submissions TO service_role;

RESET client_min_messages;
