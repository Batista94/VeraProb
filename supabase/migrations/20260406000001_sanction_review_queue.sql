-- =============================================================================
-- Migration: sanction_review_queue table (Phase 9.3 — Human-in-the-Loop)
--
-- The engine RECOMMENDS sanctions; auditors APPROVE or REJECT.
-- No SANCTION_APPLIED ever enters the ledger without explicit human action.
--
-- INV-1: Immutable fields protected by trigger (see 20260406000002).
-- INV-6: Every record carries organization_id. RLS enforces isolation.
-- INV-10: Policies use auth.jwt() ->> 'organization_id'.
-- INV-24: UNIQUE on ledger_entry_id prevents duplicate queue entries.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.sanction_review_queue (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id   UUID        NOT NULL,
  ledger_entry_id   UUID        NOT NULL,   -- FK → sla_audit_ledger_v2.id (immutable)
  set_id            TEXT        NOT NULL,
  contract_id       TEXT        NOT NULL,
  verdict_evidence  JSONB       NOT NULL,   -- VerdictEvidence bundle (INV-23)
  status            TEXT        NOT NULL DEFAULT 'pending'
    CONSTRAINT chk_srq_status
      CHECK (status IN ('pending', 'applied', 'rejected', 'disputed')),
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  reviewed_at       TIMESTAMPTZ,
  reviewed_by       UUID,
  rejection_reason  TEXT,

  -- INV-24: one queue entry per ledger event
  CONSTRAINT uq_queue_ledger_entry UNIQUE (ledger_entry_id)
);

-- ── Indexes ──────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_srq_org_status
  ON public.sanction_review_queue (organization_id, status);

-- ── Immutability trigger: block UPDATE on immutable fields (INV-1) ──────────
CREATE OR REPLACE FUNCTION public.prevent_srq_immutable_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.organization_id  IS DISTINCT FROM OLD.organization_id  OR
     NEW.ledger_entry_id  IS DISTINCT FROM OLD.ledger_entry_id  OR
     NEW.set_id           IS DISTINCT FROM OLD.set_id           OR
     NEW.contract_id      IS DISTINCT FROM OLD.contract_id      OR
     NEW.verdict_evidence IS DISTINCT FROM OLD.verdict_evidence OR
     NEW.created_at       IS DISTINCT FROM OLD.created_at
  THEN
    RAISE EXCEPTION
      'sanction_review_queue: immutable field mutation attempted (INV-1). id: %', OLD.id
    USING ERRCODE = 'restrict_violation';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_srq_no_immutable_update
  ON public.sanction_review_queue;
CREATE TRIGGER trg_srq_no_immutable_update
  BEFORE UPDATE ON public.sanction_review_queue
  FOR EACH ROW EXECUTE FUNCTION public.prevent_srq_immutable_mutation();

-- ── Block DELETE (INV-1) ─────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.prevent_srq_delete()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION
    'sanction_review_queue is append-only (INV-1). DELETE blocked. id: %', OLD.id
  USING ERRCODE = 'restrict_violation';
END;
$$;

DROP TRIGGER IF EXISTS trg_srq_no_delete ON public.sanction_review_queue;
CREATE TRIGGER trg_srq_no_delete
  BEFORE DELETE ON public.sanction_review_queue
  FOR EACH ROW EXECUTE FUNCTION public.prevent_srq_delete();

-- ── RLS (INV-6, INV-10) ──────────────────────────────────────────────────────
ALTER TABLE public.sanction_review_queue ENABLE ROW LEVEL SECURITY;

-- AUDITOR and TENANT_ADMIN can read their own org's queue
DROP POLICY IF EXISTS srq_select_own_org ON public.sanction_review_queue;
CREATE POLICY srq_select_own_org
  ON public.sanction_review_queue
  FOR SELECT
  USING (
    organization_id::text = (auth.jwt() ->> 'organization_id')
    AND (auth.jwt() ->> 'role') IN ('admin', 'auditor')
  );

-- AUDITOR and TENANT_ADMIN can update status (approve/reject)
DROP POLICY IF EXISTS srq_update_own_org ON public.sanction_review_queue;
CREATE POLICY srq_update_own_org
  ON public.sanction_review_queue
  FOR UPDATE
  USING (
    organization_id::text = (auth.jwt() ->> 'organization_id')
    AND (auth.jwt() ->> 'role') IN ('admin', 'auditor')
  );

-- Service role (engine, trigger) can insert
DROP POLICY IF EXISTS srq_insert_service ON public.sanction_review_queue;
CREATE POLICY srq_insert_service
  ON public.sanction_review_queue
  FOR INSERT
  WITH CHECK (true);

-- ── Supabase Realtime (for live queue notifications <30s) ─────────────────
ALTER PUBLICATION supabase_realtime ADD TABLE public.sanction_review_queue;
