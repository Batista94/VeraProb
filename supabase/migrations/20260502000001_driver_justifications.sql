-- Suppress DROP TRIGGER/POLICY IF EXISTS NOTICEs (objects don't exist on fresh reset).
SET client_min_messages TO 'WARNING';

-- =============================================================================
-- Migration: contractor_justifications + justification_evidence_uploads (Phase 9.8.J)
--
-- Provides the forensic justification record for contested SLA events.
-- Every justification links to a specific audit event via set_id + contract_id.
--
-- INV-1:  Immutable fields protected by triggers (identity + submission context).
-- INV-7:  Append-only evidence — no DELETE or evidence mutation allowed.
-- INV-8:  Evidence SHA-256 hash (content_hash) is mandatory for every upload.
-- INV-9:  All timestamps are UTC (timestamptz).
-- INV-22: Every decision is logged with actor ID in the immutable ledger.
-- =============================================================================

-- ── 1. contractor_justifications ─────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.contractor_justifications (
  id                    UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id       UUID        NOT NULL,
  contract_id           TEXT        NOT NULL,
  set_id                TEXT        NOT NULL,

  -- Null for operator-entered; UUID of token used for self-service submission.
  submitted_by_token    UUID,

  category              TEXT        NOT NULL
    CONSTRAINT chk_cj_category
      CHECK (category IN (
        'MECHANICAL', 'FORCE_MAJEURE', 'TRAFFIC',
        'ROUTE_DEVIATION', 'COMMUNICATION', 'OTHER'
      )),

  description           TEXT        NOT NULL
    CONSTRAINT chk_cj_description_length
      CHECK (char_length(trim(description)) >= 20),

  status                TEXT        NOT NULL DEFAULT 'PENDING'
    CONSTRAINT chk_cj_status
      CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED')),

  reviewed_by_user_id   UUID,
  reviewed_at_utc       TIMESTAMPTZ,
  created_at_utc        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── Indexes ───────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_cj_org_status
  ON public.contractor_justifications (organization_id, status);

CREATE INDEX IF NOT EXISTS idx_cj_org_contract
  ON public.contractor_justifications (organization_id, contract_id);

CREATE INDEX IF NOT EXISTS idx_cj_set_id
  ON public.contractor_justifications (set_id);

-- ── Immutability trigger (INV-1) ─────────────────────────────────────────────
-- Locks identity + submission context fields. Allows status review fields only.
CREATE OR REPLACE FUNCTION public.prevent_cj_immutable_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.organization_id    IS DISTINCT FROM OLD.organization_id    OR
     NEW.contract_id        IS DISTINCT FROM OLD.contract_id        OR
     NEW.set_id             IS DISTINCT FROM OLD.set_id             OR
     NEW.submitted_by_token IS DISTINCT FROM OLD.submitted_by_token OR
     NEW.category           IS DISTINCT FROM OLD.category           OR
     NEW.description        IS DISTINCT FROM OLD.description        OR
     NEW.created_at_utc     IS DISTINCT FROM OLD.created_at_utc
  THEN
    RAISE EXCEPTION
      'contractor_justifications: immutable field mutation attempted (INV-1). id: %', OLD.id
    USING ERRCODE = 'restrict_violation';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_cj_no_immutable_update
  ON public.contractor_justifications;
CREATE TRIGGER trg_cj_no_immutable_update
  BEFORE UPDATE ON public.contractor_justifications
  FOR EACH ROW EXECUTE FUNCTION public.prevent_cj_immutable_mutation();

-- ── Block DELETE (INV-7) ──────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.prevent_cj_delete()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION
    'contractor_justifications is append-only (INV-7). DELETE blocked. id: %', OLD.id
  USING ERRCODE = 'restrict_violation';
END;
$$;

DROP TRIGGER IF EXISTS trg_cj_no_delete ON public.contractor_justifications;
CREATE TRIGGER trg_cj_no_delete
  BEFORE DELETE ON public.contractor_justifications
  FOR EACH ROW EXECUTE FUNCTION public.prevent_cj_delete();

-- ── RLS (INV-1, INV-6) ───────────────────────────────────────────────────────
ALTER TABLE public.contractor_justifications ENABLE ROW LEVEL SECURITY;

-- Org members (admin/operator/auditor) can read their own org's justifications
DROP POLICY IF EXISTS cj_select_own_org ON public.contractor_justifications;
CREATE POLICY cj_select_own_org
  ON public.contractor_justifications
  FOR SELECT
  USING (
    organization_id::text = (auth.jwt() ->> 'organization_id')
    AND (auth.jwt() ->> 'role') IN ('admin', 'operator', 'auditor')
  );

-- SuperAdmin can read across all orgs (no org filter, read-only per requirements)
DROP POLICY IF EXISTS cj_select_super_admin ON public.contractor_justifications;
CREATE POLICY cj_select_super_admin
  ON public.contractor_justifications
  FOR SELECT
  USING (
    (auth.jwt() -> 'app_metadata' ->> 'super_admin')::boolean IS TRUE
  );

-- Operator/admin manual entry (authenticated path)
DROP POLICY IF EXISTS cj_insert_operator ON public.contractor_justifications;
CREATE POLICY cj_insert_operator
  ON public.contractor_justifications
  FOR INSERT
  WITH CHECK (
    organization_id::text = (auth.jwt() ->> 'organization_id')
    AND (auth.jwt() ->> 'role') IN ('admin', 'operator')
  );

-- Operator/admin can update (approve/reject) — immutable-field trigger enforces limits
DROP POLICY IF EXISTS cj_update_operator ON public.contractor_justifications;
CREATE POLICY cj_update_operator
  ON public.contractor_justifications
  FOR UPDATE
  USING (
    organization_id::text = (auth.jwt() ->> 'organization_id')
    AND (auth.jwt() ->> 'role') IN ('admin', 'operator')
  );

-- Service role / SECURITY DEFINER RPCs can insert (tokenized self-service path)
DROP POLICY IF EXISTS cj_insert_service ON public.contractor_justifications;
CREATE POLICY cj_insert_service
  ON public.contractor_justifications
  FOR INSERT
  WITH CHECK (true);


-- ── 2. justification_evidence_uploads ────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.justification_evidence_uploads (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  justification_id  UUID        NOT NULL
    REFERENCES public.contractor_justifications(id),
  organization_id   UUID        NOT NULL,
  file_name         TEXT        NOT NULL,

  -- SHA-256 hex digest (64 chars) computed server-side (INV-8)
  content_hash      TEXT        NOT NULL
    CONSTRAINT chk_jeu_content_hash_len
      CHECK (char_length(content_hash) = 64),

  storage_path      TEXT        NOT NULL,
  uploaded_at_utc   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── Indexes ───────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_jeu_justification_id
  ON public.justification_evidence_uploads (justification_id);

CREATE INDEX IF NOT EXISTS idx_jeu_org_id
  ON public.justification_evidence_uploads (organization_id);

-- ── Full append-only (INV-7, INV-8 — evidence is forensic) ───────────────────
CREATE OR REPLACE FUNCTION public.prevent_jeu_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    RAISE EXCEPTION
      'justification_evidence_uploads is fully immutable (INV-7/INV-8). id: %', OLD.id
    USING ERRCODE = 'restrict_violation';
  END IF;
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION
      'justification_evidence_uploads is append-only (INV-7). DELETE blocked. id: %', OLD.id
    USING ERRCODE = 'restrict_violation';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_jeu_no_update ON public.justification_evidence_uploads;
CREATE TRIGGER trg_jeu_no_update
  BEFORE UPDATE ON public.justification_evidence_uploads
  FOR EACH ROW EXECUTE FUNCTION public.prevent_jeu_mutation();

DROP TRIGGER IF EXISTS trg_jeu_no_delete ON public.justification_evidence_uploads;
CREATE TRIGGER trg_jeu_no_delete
  BEFORE DELETE ON public.justification_evidence_uploads
  FOR EACH ROW EXECUTE FUNCTION public.prevent_jeu_mutation();

-- ── RLS ───────────────────────────────────────────────────────────────────────
ALTER TABLE public.justification_evidence_uploads ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS jeu_select_own_org ON public.justification_evidence_uploads;
CREATE POLICY jeu_select_own_org
  ON public.justification_evidence_uploads
  FOR SELECT
  USING (
    organization_id::text = (auth.jwt() ->> 'organization_id')
    AND (auth.jwt() ->> 'role') IN ('admin', 'operator', 'auditor')
  );

DROP POLICY IF EXISTS jeu_select_super_admin ON public.justification_evidence_uploads;
CREATE POLICY jeu_select_super_admin
  ON public.justification_evidence_uploads
  FOR SELECT
  USING (
    (auth.jwt() -> 'app_metadata' ->> 'super_admin')::boolean IS TRUE
  );

DROP POLICY IF EXISTS jeu_insert_operator ON public.justification_evidence_uploads;
CREATE POLICY jeu_insert_operator
  ON public.justification_evidence_uploads
  FOR INSERT
  WITH CHECK (
    organization_id::text = (auth.jwt() ->> 'organization_id')
    AND (auth.jwt() ->> 'role') IN ('admin', 'operator')
  );

-- Service role / Edge Function can insert (anon driver upload path)
DROP POLICY IF EXISTS jeu_insert_service ON public.justification_evidence_uploads;
CREATE POLICY jeu_insert_service
  ON public.justification_evidence_uploads
  FOR INSERT
  WITH CHECK (true);

-- ── Supabase Realtime ─────────────────────────────────────────────────────────
ALTER PUBLICATION supabase_realtime ADD TABLE public.contractor_justifications;
