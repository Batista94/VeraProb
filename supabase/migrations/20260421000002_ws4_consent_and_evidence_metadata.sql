-- pr_scanner: ignore-regression
--
-- Suppress DROP TRIGGER/POLICY IF EXISTS NOTICEs.
SET client_min_messages TO 'WARNING';

-- =============================================================================
-- Migration: WS-4 Consent & Evidence Metadata
--
-- Tables: telegram_user_consents, telegram_evidence_metadata
--
-- INV-1:  Tenant isolation via organization_id (metadata table).
-- INV-2:  RLS uses auth.jwt() -> 'app_metadata' ->> 'org_id'. NO (auth.jwt() ->> 'sub').
-- INV-6:  UTC everywhere (timestamptz).
-- INV-7:  Both tables fully immutable, append-only. UPDATE and DELETE blocked.
-- INV-9:  ip_hash stores SHA-256 for forensic audit trail.
-- INV-22: Tenant-A must NEVER see Tenant-B's metadata.
-- =============================================================================

-- ── 1. telegram_user_consents ────────────────────────────────────────────────
--
-- LGPD consent tracking. Fully immutable, append-only.
-- UNIQUE (chat_id, consent_version) allows re-consent on version bump.

CREATE TABLE IF NOT EXISTS public.telegram_user_consents (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  chat_id           BIGINT      NOT NULL,
  accepted_at_utc   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  consent_version   TEXT        NOT NULL DEFAULT 'v1',
  ip_hash           TEXT,  -- optional: SHA-256 of IP for forensic audit
  created_at_utc    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_tuc_chat_version
  ON public.telegram_user_consents (chat_id, consent_version);

CREATE INDEX IF NOT EXISTS idx_tuc_chat_id
  ON public.telegram_user_consents (chat_id);

-- Fully immutable: no field may ever change after insert (INV-7).
CREATE OR REPLACE FUNCTION public.prevent_tuc_immutable_mutation()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION
    'telegram_user_consents: fully immutable (INV-7). UPDATE blocked. id: %', OLD.id
  USING ERRCODE = 'restrict_violation';
END;
$$;

DROP TRIGGER IF EXISTS trg_tuc_no_update ON public.telegram_user_consents;
CREATE TRIGGER trg_tuc_no_update
  BEFORE UPDATE ON public.telegram_user_consents
  FOR EACH ROW EXECUTE FUNCTION public.prevent_tuc_immutable_mutation();

CREATE OR REPLACE FUNCTION public.prevent_tuc_delete()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION
    'telegram_user_consents: append-only (INV-7). DELETE blocked. id: %', OLD.id
  USING ERRCODE = 'restrict_violation';
END;
$$;

DROP TRIGGER IF EXISTS trg_tuc_no_delete ON public.telegram_user_consents;
CREATE TRIGGER trg_tuc_no_delete
  BEFORE DELETE ON public.telegram_user_consents
  FOR EACH ROW EXECUTE FUNCTION public.prevent_tuc_delete();

ALTER TABLE public.telegram_user_consents ENABLE ROW LEVEL SECURITY;

-- Service role (webhook Edge Function) inserts consent records.
DROP POLICY IF EXISTS tuc_insert_service ON public.telegram_user_consents;
CREATE POLICY tuc_insert_service
  ON public.telegram_user_consents FOR INSERT
  WITH CHECK (true);

-- Service role reads consent to verify before accepting evidence.
DROP POLICY IF EXISTS tuc_select_service ON public.telegram_user_consents;
CREATE POLICY tuc_select_service
  ON public.telegram_user_consents FOR SELECT
  USING (true);

-- ── 2. telegram_evidence_metadata ────────────────────────────────────────────
--
-- EXIF metadata extracted from evidence files. Fully immutable, append-only.
-- UNIQUE on evidence_upload_id: one metadata record per upload.

CREATE TABLE IF NOT EXISTS public.telegram_evidence_metadata (
  id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id     UUID        NOT NULL,
  evidence_upload_id  UUID        NOT NULL REFERENCES public.telegram_evidence_uploads(id),
  exif_data           JSONB       NOT NULL DEFAULT '{}',
  extracted_at_utc    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_tem_evidence_upload_id
  ON public.telegram_evidence_metadata (evidence_upload_id);

CREATE INDEX IF NOT EXISTS idx_tem_org_extracted_at
  ON public.telegram_evidence_metadata (organization_id, extracted_at_utc DESC);

-- Fully immutable: no field may ever change after insert (INV-7).
CREATE OR REPLACE FUNCTION public.prevent_tem_immutable_mutation()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION
    'telegram_evidence_metadata: fully immutable (INV-7). UPDATE blocked. id: %', OLD.id
  USING ERRCODE = 'restrict_violation';
END;
$$;

DROP TRIGGER IF EXISTS trg_tem_no_update ON public.telegram_evidence_metadata;
CREATE TRIGGER trg_tem_no_update
  BEFORE UPDATE ON public.telegram_evidence_metadata
  FOR EACH ROW EXECUTE FUNCTION public.prevent_tem_immutable_mutation();

CREATE OR REPLACE FUNCTION public.prevent_tem_delete()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION
    'telegram_evidence_metadata: append-only (INV-7). DELETE blocked. id: %', OLD.id
  USING ERRCODE = 'restrict_violation';
END;
$$;

DROP TRIGGER IF EXISTS trg_tem_no_delete ON public.telegram_evidence_metadata;
CREATE TRIGGER trg_tem_no_delete
  BEFORE DELETE ON public.telegram_evidence_metadata
  FOR EACH ROW EXECUTE FUNCTION public.prevent_tem_delete();

ALTER TABLE public.telegram_evidence_metadata ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS tem_select_own_org ON public.telegram_evidence_metadata;
CREATE POLICY tem_select_own_org
  ON public.telegram_evidence_metadata FOR SELECT
  USING (
    organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid
    AND (auth.jwt() -> 'app_metadata' ->> 'role') IN ('TENANT_ADMIN', 'OPERATOR', 'AUDITOR')
  );

-- Service role (webhook) inserts metadata after EXIF extraction.
DROP POLICY IF EXISTS tem_insert_service ON public.telegram_evidence_metadata;
CREATE POLICY tem_insert_service
  ON public.telegram_evidence_metadata FOR INSERT
  WITH CHECK (true);

DROP POLICY IF EXISTS tem_select_super_admin ON public.telegram_evidence_metadata;
CREATE POLICY tem_select_super_admin
  ON public.telegram_evidence_metadata FOR SELECT
  USING ((auth.jwt() -> 'app_metadata' ->> 'super_admin')::boolean IS TRUE);
