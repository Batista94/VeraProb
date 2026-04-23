-- =============================================================================
-- Migration: Telegram Evidence Categories (Menu Pai Universal)
--
-- Table: telegram_evidence_categories
--   Stores driver-assigned category tags for evidence uploads.
--   Separate from telegram_evidence_uploads to preserve full immutability (INV-7).
--
-- INV-1:  Tenant isolation via organization_id.
-- INV-7:  Append-only — UPDATE and DELETE blocked by triggers.
-- INV-18: Category value constrained to known enum; Telegram metadata untrusted.
-- =============================================================================

SET client_min_messages TO 'WARNING';

-- ── 1. Table ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.telegram_evidence_categories (
  id                    UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id       UUID        NOT NULL,
  evidence_upload_id    UUID        NOT NULL
    REFERENCES public.telegram_evidence_uploads(id),
  category              TEXT        NOT NULL
    CONSTRAINT chk_tec_category CHECK (
      category IN ('estado', 'doc', 'oper', 'incidente', 'outros')
    ),
  tagged_at_utc         TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- One category per evidence (driver picks once; re-tag not allowed per INV-7)
  CONSTRAINT uq_tec_evidence UNIQUE (evidence_upload_id)
);

-- ── 2. Indexes ───────────────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_tec_org_category
  ON public.telegram_evidence_categories (organization_id, category);

CREATE INDEX IF NOT EXISTS idx_tec_evidence_upload
  ON public.telegram_evidence_categories (evidence_upload_id);

-- ── 3. Immutability triggers (INV-7) ─────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.prevent_tec_update()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION
    'telegram_evidence_categories: fully immutable (INV-7). UPDATE blocked. id: %', OLD.id
  USING ERRCODE = 'restrict_violation';
END;
$$;

DROP TRIGGER IF EXISTS trg_tec_no_update ON public.telegram_evidence_categories;
CREATE TRIGGER trg_tec_no_update
  BEFORE UPDATE ON public.telegram_evidence_categories
  FOR EACH ROW EXECUTE FUNCTION public.prevent_tec_update();

CREATE OR REPLACE FUNCTION public.prevent_tec_delete()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION
    'telegram_evidence_categories: append-only (INV-7). DELETE blocked. id: %', OLD.id
  USING ERRCODE = 'restrict_violation';
END;
$$;

DROP TRIGGER IF EXISTS trg_tec_no_delete ON public.telegram_evidence_categories;
CREATE TRIGGER trg_tec_no_delete
  BEFORE DELETE ON public.telegram_evidence_categories
  FOR EACH ROW EXECUTE FUNCTION public.prevent_tec_delete();

-- ── 4. RLS ───────────────────────────────────────────────────────────────────

ALTER TABLE public.telegram_evidence_categories ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS tec_select_own_org ON public.telegram_evidence_categories;
CREATE POLICY tec_select_own_org
  ON public.telegram_evidence_categories FOR SELECT
  USING (
    organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid
    AND (auth.jwt() -> 'app_metadata' ->> 'role') IN ('TENANT_ADMIN', 'OPERATOR', 'AUDITOR')
  );

-- Service role (webhook Edge Function) inserts categories on behalf of driver.
DROP POLICY IF EXISTS tec_insert_service ON public.telegram_evidence_categories;
CREATE POLICY tec_insert_service
  ON public.telegram_evidence_categories FOR INSERT
  WITH CHECK (true);

DROP POLICY IF EXISTS tec_select_super_admin ON public.telegram_evidence_categories;
CREATE POLICY tec_select_super_admin
  ON public.telegram_evidence_categories FOR SELECT
  USING ((auth.jwt() -> 'app_metadata' ->> 'super_admin')::boolean IS TRUE);
