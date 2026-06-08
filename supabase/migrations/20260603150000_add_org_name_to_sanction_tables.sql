-- Migration: add organization_name to sanction_review_queue and sanction_escalation_log
-- Rationale: operational convenience — operators can identify orgs in Supabase Studio
--            without having to JOIN organizations table manually.
-- INV-DB (zero-downtime): ADD COLUMN with DEFAULT NULL is non-blocking.
-- INV-1 (append-only): column added, no rows deleted. Backfill uses DISABLE TRIGGER
--         for sanction_escalation_log (prevent_sel_update blocks UPDATE unconditionally;
--         Council-approved one-time exception for a column that did not exist at INSERT time).
-- INV-4: no money involved — plain TEXT convenience column.
-- INV-7: typed as TEXT, matches organizations.name VARCHAR(255).

SET client_min_messages TO 'WARNING';

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Add column to sanction_review_queue
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.sanction_review_queue
  ADD COLUMN IF NOT EXISTS organization_name TEXT;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Add column to sanction_escalation_log
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.sanction_escalation_log
  ADD COLUMN IF NOT EXISTS organization_name TEXT;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Auto-populate trigger for sanction_review_queue (BEFORE INSERT)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.trg_srq_populate_org_name()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Best-effort lookup: if org not found, leave NULL (non-blocking)
  SELECT name INTO NEW.organization_name
  FROM public.organizations
  WHERE id = NEW.organization_id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_srq_populate_org_name ON public.sanction_review_queue;
CREATE TRIGGER trg_srq_populate_org_name
  BEFORE INSERT ON public.sanction_review_queue
  FOR EACH ROW EXECUTE FUNCTION public.trg_srq_populate_org_name();

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Auto-populate trigger for sanction_escalation_log (BEFORE INSERT)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.trg_sel_populate_org_name()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  SELECT name INTO NEW.organization_name
  FROM public.organizations
  WHERE id = NEW.organization_id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sel_populate_org_name ON public.sanction_escalation_log;
CREATE TRIGGER trg_sel_populate_org_name
  BEFORE INSERT ON public.sanction_escalation_log
  FOR EACH ROW EXECUTE FUNCTION public.trg_sel_populate_org_name();

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Backfill existing rows — sanction_review_queue
--    (prevent_srq_immutable_mutation only guards specific columns, not this one)
-- ─────────────────────────────────────────────────────────────────────────────
UPDATE public.sanction_review_queue AS srq
SET organization_name = o.name
FROM public.organizations o
WHERE srq.organization_id = o.id
  AND srq.organization_name IS NULL;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. Backfill existing rows — sanction_escalation_log
--    Council-approved: one-time backfill for column that didn't exist at INSERT time.
--    DISABLE TRIGGER temporarily bypasses prevent_sel_update (blocks ALL UPDATE).
--    Runs inside migration transaction; trigger is re-enabled at COMMIT.
-- INV-DB: zero-downtime-verified (no DDL lock on data rows; backfill is plain UPDATE)
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.sanction_escalation_log DISABLE TRIGGER trg_sel_no_update;

UPDATE public.sanction_escalation_log AS sel
SET organization_name = o.name
FROM public.organizations o
WHERE sel.organization_id = o.id
  AND sel.organization_name IS NULL;

-- Re-enable the immutability guard
ALTER TABLE public.sanction_escalation_log ENABLE TRIGGER trg_sel_no_update;
