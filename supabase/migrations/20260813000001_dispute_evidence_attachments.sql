-- =============================================================================
-- Migration: dispute_evidence_attachments — Cryptographic Evidence Sealing
-- Purpose:   Material probatório vinculado a disputas. SHA-256 selado no
--            ingest (INV-9) e re-verificado server-side (ADD-2). Tenant-isolated.
--
-- Invariants: INV-1, INV-2, INV-3, INV-6, INV-9, INV-22, INV-DB.
-- Entity (not VO): possui id próprio, ciclo de vida (deleted_at), proveniência.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.dispute_evidence_attachments (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id   UUID        NOT NULL REFERENCES public.organizations(id),
  queue_entry_id    UUID        NOT NULL REFERENCES public.sanction_review_queue(id),

  -- File metadata (sealed at ingest — immutable after INSERT)
  storage_path      TEXT        NOT NULL,
  file_name         TEXT        NOT NULL,
  mime_type         TEXT        NOT NULL
    CONSTRAINT chk_evidence_mime CHECK (
      mime_type IN ('image/jpeg','image/png','application/pdf',
                    'image/heic','image/heif','image/webp')
    ),
  file_size_bytes   BIGINT      NOT NULL
    CONSTRAINT chk_evidence_size CHECK (file_size_bytes > 0 AND file_size_bytes <= 10485760),

  -- Cryptographic seal (INV-9)
  sha256_hash       TEXT        NOT NULL
    CONSTRAINT chk_evidence_hash_format CHECK (sha256_hash ~ '^[a-f0-9]{64}$'),

  -- Server-side verification state (ADD-2, B2). NOT sealed — updated by verify RPC.
  verification_status TEXT      NOT NULL DEFAULT 'PENDING'
    CONSTRAINT chk_evidence_verif CHECK (
      verification_status IN ('PENDING','VERIFIED','MISMATCH')
    ),
  hash_verified_at  TIMESTAMPTZ,

  -- Actor provenance
  uploaded_by       UUID        NOT NULL,
  attached_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- Soft-delete (INV-DB: no hard DELETE)
  deleted_at        TIMESTAMPTZ,

  CONSTRAINT uq_dea_hash_per_queue UNIQUE (organization_id, queue_entry_id, sha256_hash)
);

-- ── Indexes ──────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_dea_org_queue
  ON public.dispute_evidence_attachments (organization_id, queue_entry_id)
  WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_dea_sha256
  ON public.dispute_evidence_attachments (organization_id, sha256_hash);

-- ── Immutability trigger: sealed fields + anti un-soft-delete (B3) ────────────
CREATE OR REPLACE FUNCTION public.prevent_dea_immutable_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  -- Sealed forensic fields can never change.
  IF NEW.organization_id IS DISTINCT FROM OLD.organization_id OR
     NEW.queue_entry_id   IS DISTINCT FROM OLD.queue_entry_id  OR
     NEW.storage_path     IS DISTINCT FROM OLD.storage_path    OR
     NEW.sha256_hash      IS DISTINCT FROM OLD.sha256_hash     OR
     NEW.file_name        IS DISTINCT FROM OLD.file_name       OR
     NEW.mime_type        IS DISTINCT FROM OLD.mime_type       OR
     NEW.file_size_bytes  IS DISTINCT FROM OLD.file_size_bytes OR
     NEW.uploaded_by      IS DISTINCT FROM OLD.uploaded_by     OR
     NEW.attached_at      IS DISTINCT FROM OLD.attached_at
  THEN
    RAISE EXCEPTION
      'dispute_evidence_attachments: immutable field mutation (INV-9). id: %', OLD.id
    USING ERRCODE = 'restrict_violation';
  END IF;

  -- B3: un-soft-delete of retracted evidence is tampering.
  IF OLD.deleted_at IS NOT NULL AND NEW.deleted_at IS NULL THEN
    RAISE EXCEPTION
      'dispute_evidence_attachments: cannot resurrect soft-deleted evidence (INV-3). id: %', OLD.id
    USING ERRCODE = 'restrict_violation';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_dea_no_immutable_update ON public.dispute_evidence_attachments;
CREATE TRIGGER trg_dea_no_immutable_update
  BEFORE UPDATE ON public.dispute_evidence_attachments
  FOR EACH ROW EXECUTE FUNCTION public.prevent_dea_immutable_mutation();

-- ── Block DELETE (append-only) ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.prevent_dea_delete()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION
    'dispute_evidence_attachments is append-only. Use soft-delete (deleted_at). id: %', OLD.id
  USING ERRCODE = 'restrict_violation';
END;
$$;
DROP TRIGGER IF EXISTS trg_dea_no_delete ON public.dispute_evidence_attachments;
CREATE TRIGGER trg_dea_no_delete
  BEFORE DELETE ON public.dispute_evidence_attachments
  FOR EACH ROW EXECUTE FUNCTION public.prevent_dea_delete();

-- ── RLS (INV-2, INV-22) ─────────────────────────────────────────────────────
ALTER TABLE public.dispute_evidence_attachments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS dea_select_own_org ON public.dispute_evidence_attachments;
CREATE POLICY dea_select_own_org
  ON public.dispute_evidence_attachments FOR SELECT
  USING (
    organization_id = ((auth.jwt() -> 'app_metadata' ->> 'org_id')::UUID)
    AND (auth.jwt() -> 'app_metadata' ->> 'role') IN ('TENANT_ADMIN', 'AUDITOR')
  );

-- INSERT only via attach_dispute_evidence RPC (B4). No direct INSERT policy for
-- authenticated — RPC is SECURITY DEFINER and validates queue ownership + path.
-- (Absence of an INSERT policy = no client-side direct insert.)

-- UPDATE: only soft-delete (set deleted_at). WITH CHECK pins org_id (B3); the
-- trigger blocks sealed-field + un-soft-delete mutations.
DROP POLICY IF EXISTS dea_update_own_org ON public.dispute_evidence_attachments;
CREATE POLICY dea_update_own_org
  ON public.dispute_evidence_attachments FOR UPDATE
  USING (
    organization_id = ((auth.jwt() -> 'app_metadata' ->> 'org_id')::UUID)
    AND (auth.jwt() -> 'app_metadata' ->> 'role') IN ('TENANT_ADMIN', 'AUDITOR')
  )
  WITH CHECK (
    organization_id = ((auth.jwt() -> 'app_metadata' ->> 'org_id')::UUID)
    AND (auth.jwt() -> 'app_metadata' ->> 'role') IN ('TENANT_ADMIN', 'AUDITOR')
  );

-- ── Data API Grants (INV-DATA-API-GRANT) ─────────────────────────────────────
-- SELECT + UPDATE (soft-delete) to authenticated. INSERT only via the
-- attach_dispute_evidence RPC (B4); DELETE never (append-only, INV-3).
--
-- Defense-in-depth: legacy ALTER DEFAULT PRIVILEGES leaks INSERT/DELETE to
-- `authenticated` on new public tables. RLS (no INSERT policy) and the
-- prevent_dea_delete trigger already block both, but we REVOKE the raw
-- privileges too so the protected path is provably the only one
-- (cf. 20260811000000_harden_client_role_grants).
GRANT SELECT, UPDATE ON TABLE public.dispute_evidence_attachments TO authenticated;
REVOKE INSERT, DELETE, TRUNCATE ON TABLE public.dispute_evidence_attachments FROM authenticated; -- INV-DB: zero-downtime-verified (privilege REVOKE, not DML; cf. 20260811000000)
REVOKE ALL ON TABLE public.dispute_evidence_attachments FROM anon; -- INV-DB: zero-downtime-verified (privilege REVOKE, not DML)
GRANT ALL ON TABLE public.dispute_evidence_attachments TO service_role;
