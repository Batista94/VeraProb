-- Suppress DROP TRIGGER/POLICY IF EXISTS NOTICEs (objects don't exist on fresh reset).
SET client_min_messages TO 'WARNING';

-- =============================================================================
-- Migration: sanction_escalation_log — append-only notification audit trail
--
-- Records every notification dispatched for a pending sanction.
-- Prepared for email (Resend) escalation in a future phase — no external
-- dependency added in Phase 9.3.
--
-- INV-1: Triggers block UPDATE and DELETE.
-- INV-6: organization_id on every record.
-- INV-10: RLS uses auth.jwt() ->> 'organization_id'.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.sanction_escalation_log (
  id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id  UUID        NOT NULL,
  queue_entry_id   UUID        NOT NULL
    REFERENCES public.sanction_review_queue (id),
  notified_user_id UUID,
  channel          TEXT        NOT NULL
    CONSTRAINT chk_sel_channel CHECK (channel IN ('in_app', 'email')),
  sent_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  delivery_status  TEXT        NOT NULL DEFAULT 'sent'
    CONSTRAINT chk_sel_delivery CHECK (
      delivery_status IN ('sent', 'delivered', 'failed')
    )
);

-- ── Index ─────────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_sel_org_entry
  ON public.sanction_escalation_log (organization_id, queue_entry_id);

-- ── Block UPDATE (INV-1) ─────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.prevent_sel_update()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION
    'sanction_escalation_log is immutable (INV-1). UPDATE blocked. id: %', OLD.id
  USING ERRCODE = 'restrict_violation';
END;
$$;

DROP TRIGGER IF EXISTS trg_sel_no_update ON public.sanction_escalation_log;
CREATE TRIGGER trg_sel_no_update
  BEFORE UPDATE ON public.sanction_escalation_log
  FOR EACH ROW EXECUTE FUNCTION public.prevent_sel_update();

-- ── Block DELETE (INV-1) ─────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.prevent_sel_delete()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION
    'sanction_escalation_log is immutable (INV-1). DELETE blocked. id: %', OLD.id
  USING ERRCODE = 'restrict_violation';
END;
$$;

DROP TRIGGER IF EXISTS trg_sel_no_delete ON public.sanction_escalation_log;
CREATE TRIGGER trg_sel_no_delete
  BEFORE DELETE ON public.sanction_escalation_log
  FOR EACH ROW EXECUTE FUNCTION public.prevent_sel_delete();

-- ── RLS (INV-6, INV-10) ──────────────────────────────────────────────────────
ALTER TABLE public.sanction_escalation_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS sel_select_own_org ON public.sanction_escalation_log;
CREATE POLICY sel_select_own_org
  ON public.sanction_escalation_log
  FOR SELECT
  USING (
    organization_id::text = (auth.jwt() ->> 'organization_id')
    AND (auth.jwt() ->> 'role') IN ('admin', 'auditor')
  );

DROP POLICY IF EXISTS sel_insert_service ON public.sanction_escalation_log;
CREATE POLICY sel_insert_service
  ON public.sanction_escalation_log
  FOR INSERT
  WITH CHECK (true);
