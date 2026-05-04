-- pr_scanner: ignore-regression
-- =============================================================================
-- Stage A.4 — System Audit Log: Governance Fields
-- =============================================================================
-- Extends system_audit_log with governance-specific columns:
--   - reason: mandatory justification for governance changes
--   - actor_type: HUMAN | IMPERSONATOR | SYSTEM
--   - impersonator_id: UUID of the impersonating super_admin (when actor_type = 'IMPERSONATOR')
--
-- INV-3:  Ledger APPEND-ONLY — system_audit_log already has no_update/no_delete rules.
-- INV-10: Error Visibility — trigger enforces reason NOT NULL for governance events.
-- =============================================================================

-- ── Step 1: Add new columns ──────────────────────────────────────────────────

-- Must temporarily drop immutability rules to ALTER the table
DROP RULE IF EXISTS system_audit_log_no_update ON public.system_audit_log;
DROP RULE IF EXISTS system_audit_log_no_delete ON public.system_audit_log;

ALTER TABLE public.system_audit_log
  ADD COLUMN IF NOT EXISTS reason TEXT;

ALTER TABLE public.system_audit_log
  ADD COLUMN IF NOT EXISTS actor_type TEXT
    CHECK (actor_type IS NULL OR actor_type IN ('HUMAN', 'IMPERSONATOR', 'SYSTEM'));

ALTER TABLE public.system_audit_log
  ADD COLUMN IF NOT EXISTS impersonator_id UUID;

-- ── Step 2: Re-create immutability rules ─────────────────────────────────────
CREATE OR REPLACE RULE system_audit_log_no_update AS
  ON UPDATE TO public.system_audit_log DO INSTEAD NOTHING;

CREATE OR REPLACE RULE system_audit_log_no_delete AS
  ON DELETE TO public.system_audit_log DO INSTEAD NOTHING;

-- ── Step 3: Trigger to enforce reason NOT NULL for governance events ─────────
CREATE OR REPLACE FUNCTION public.system_audit_log_governance_check()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.event_type IN (
    'QUOTA_CHANGE',
    'STATUS_CHANGE',
    'LIMIT_CHANGE',
    'SECRET_ROTATION',
    'IMPERSONATION_START',
    'IMPERSONATION_REVOKE',
    'OPERATIONAL_PARAM_CHANGE'
  ) THEN
    IF NEW.reason IS NULL OR trim(NEW.reason) = '' THEN
      RAISE EXCEPTION 'Governance event "%" requires a non-empty reason', NEW.event_type
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  -- Validate impersonator_id consistency
  IF NEW.actor_type = 'IMPERSONATOR' AND NEW.impersonator_id IS NULL THEN
    RAISE EXCEPTION 'actor_type IMPERSONATOR requires impersonator_id'
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_system_audit_log_governance_check ON public.system_audit_log;
CREATE TRIGGER trg_system_audit_log_governance_check
  BEFORE INSERT ON public.system_audit_log
  FOR EACH ROW EXECUTE FUNCTION public.system_audit_log_governance_check();

-- ── Step 4: Index for governance event queries ───────────────────────────────
CREATE INDEX IF NOT EXISTS idx_system_audit_log_actor_type
  ON public.system_audit_log (actor_type, occurred_at DESC)
  WHERE actor_type IS NOT NULL;

COMMENT ON COLUMN public.system_audit_log.reason IS
  'Mandatory justification for governance events (QUOTA_CHANGE, STATUS_CHANGE, etc.). '
  'Enforced by trg_system_audit_log_governance_check trigger.';

COMMENT ON COLUMN public.system_audit_log.actor_type IS
  'HUMAN = direct user action, IMPERSONATOR = super_admin acting as tenant, SYSTEM = automated.';

COMMENT ON COLUMN public.system_audit_log.impersonator_id IS
  'UUID of the impersonating super_admin. Required when actor_type = IMPERSONATOR.';
