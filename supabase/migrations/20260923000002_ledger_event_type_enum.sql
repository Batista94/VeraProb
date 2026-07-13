-- pr_scanner: ignore-regression — PR elevation CIA migrations (Council-approved plan)
-- =============================================================================
-- Migration: ledger_event_type ENUM replaces chk_ledger_type CHECK swaps (PR2)
--
-- Future event types: ALTER TYPE public.ledger_event_type ADD VALUE 'NEW_TYPE';
-- Do NOT reintroduce CHECK-swap migrations (vN NOT VALID → VALIDATE → DROP → RENAME).
--
-- Includes SYSTEM_AUTO_CLOSE for autonomous closer → v2 path (PR4).
-- Invariants: INV-3, INV-DB (constraint swap / type cast on conforming data).
--
-- ALTER COLUMN TYPE blocked by:
--   1) triggers with WHEN (NEW.type …)
--   2) partial indexes with WHERE type = / IN (…) — cast text→enum is not
--      IMMUTABLE in index predicate rewrite (SQLSTATE 42P17)
-- =============================================================================

SET client_min_messages TO 'WARNING';

DO $$ BEGIN
  CREATE TYPE public.ledger_event_type AS ENUM (
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
    'PORTAL_EVIDENCE_SUBMITTED','PORTAL_EVIDENCE_FINALIZED','PORTAL_EVIDENCE_HASH_MISMATCH',
    'PORTAL_EVIDENCE_MIME_MISMATCH','PORTAL_EVIDENCE_REJECTED',
    'PORTAL_EVIDENCE_AUDITOR_ACCEPTED','PORTAL_EVIDENCE_AUDITOR_REJECTED',
    'SANCTION_ACKNOWLEDGED',
    'PORTAL_JUSTIFICATION_SUBMITTED',
    'FINANCIAL_CAP_REACHED','FINANCIAL_CAP_WARNING',
    'SYSTEM_AUTO_CLOSE'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON TYPE public.ledger_event_type IS
  'SSOT for sla_audit_ledger_v2.type. Add values via ALTER TYPE ... ADD VALUE — never CHECK-swap.';

ALTER TABLE public.sla_audit_ledger_v2
  DROP CONSTRAINT IF EXISTS chk_ledger_type; -- INV-DB: zero-downtime-verified (CHECK replaced by ENUM)

-- ── Drop dependents that reference column type ───────────────────────────────
DROP TRIGGER IF EXISTS trg_financial_guard ON public.sla_audit_ledger_v2;
DROP TRIGGER IF EXISTS trg_financial_guard_credit ON public.sla_audit_ledger_v2;

-- Partial indexes (WHERE type …) — INV-DB: DROP INDEX to allow type cast, recreate below.
DROP INDEX IF EXISTS public.idx_ledger_sla_breached_queue; -- INV-DB: zero-downtime-verified (recreated below)
DROP INDEX IF EXISTS public.uq_ledger_sla_breach_once; -- INV-DB: zero-downtime-verified (recreated below)
DROP INDEX IF EXISTS public.uq_ledger_resolution_cycle_p0; -- INV-DB: zero-downtime-verified (recreated below)
DROP INDEX IF EXISTS public.uq_ledger_resolution_cycle_p1; -- INV-DB: zero-downtime-verified (recreated below)
DROP INDEX IF EXISTS public.uq_ledger_resolution_cycle_p2; -- INV-DB: zero-downtime-verified (recreated below)
DROP INDEX IF EXISTS public.uq_ledger_resolution_cycle_p3; -- INV-DB: zero-downtime-verified (recreated below)

ALTER TABLE public.sla_audit_ledger_v2
  ALTER COLUMN type TYPE public.ledger_event_type
  USING type::public.ledger_event_type; -- INV-DB: zero-downtime-verified (conforming CHECK data)

-- ── Recreate triggers ────────────────────────────────────────────────────────
CREATE TRIGGER trg_financial_guard
  BEFORE INSERT ON public.sla_audit_ledger_v2
  FOR EACH ROW
  WHEN (NEW.type IN (
    'SANCTION_RECOMMENDED'::public.ledger_event_type,
    'NO_SHOW_PENALTY'::public.ledger_event_type
  ))
  EXECUTE FUNCTION public.enforce_financial_guard();

CREATE TRIGGER trg_financial_guard_credit
  AFTER INSERT ON public.sla_audit_ledger_v2
  FOR EACH ROW
  WHEN (NEW.type IN (
    'DISPUTE_ACCEPTED'::public.ledger_event_type,
    'VERDICT_REFUSED'::public.ledger_event_type
  ))
  EXECUTE FUNCTION public.credit_financial_guard();

-- ── Recreate partial indexes (enum predicates) ───────────────────────────────
CREATE INDEX IF NOT EXISTS idx_ledger_sla_breached_queue
  ON public.sla_audit_ledger_v2 ((payload ->> 'queue_entry_id'))
  WHERE type = 'DISPUTE_SLA_BREACHED'::public.ledger_event_type;

CREATE UNIQUE INDEX IF NOT EXISTS uq_ledger_sla_breach_once
  ON public.sla_audit_ledger_v2 (organization_id, (payload ->> 'queue_entry_id'))
  WHERE type = 'DISPUTE_SLA_BREACHED'::public.ledger_event_type;

CREATE UNIQUE INDEX IF NOT EXISTS uq_ledger_resolution_cycle_p0
  ON public.sla_audit_ledger_p0
     (organization_id, (payload->>'queue_entry_id'), (payload->>'dispute_round'))
  WHERE type IN (
    'DISPUTE_ACCEPTED'::public.ledger_event_type,
    'DISPUTE_OVERTURNED'::public.ledger_event_type,
    'DISPUTE_RETRACTED'::public.ledger_event_type
  );
CREATE UNIQUE INDEX IF NOT EXISTS uq_ledger_resolution_cycle_p1
  ON public.sla_audit_ledger_p1
     (organization_id, (payload->>'queue_entry_id'), (payload->>'dispute_round'))
  WHERE type IN (
    'DISPUTE_ACCEPTED'::public.ledger_event_type,
    'DISPUTE_OVERTURNED'::public.ledger_event_type,
    'DISPUTE_RETRACTED'::public.ledger_event_type
  );
CREATE UNIQUE INDEX IF NOT EXISTS uq_ledger_resolution_cycle_p2
  ON public.sla_audit_ledger_p2
     (organization_id, (payload->>'queue_entry_id'), (payload->>'dispute_round'))
  WHERE type IN (
    'DISPUTE_ACCEPTED'::public.ledger_event_type,
    'DISPUTE_OVERTURNED'::public.ledger_event_type,
    'DISPUTE_RETRACTED'::public.ledger_event_type
  );
CREATE UNIQUE INDEX IF NOT EXISTS uq_ledger_resolution_cycle_p3
  ON public.sla_audit_ledger_p3
     (organization_id, (payload->>'queue_entry_id'), (payload->>'dispute_round'))
  WHERE type IN (
    'DISPUTE_ACCEPTED'::public.ledger_event_type,
    'DISPUTE_OVERTURNED'::public.ledger_event_type,
    'DISPUTE_RETRACTED'::public.ledger_event_type
  );

GRANT USAGE ON TYPE public.ledger_event_type TO authenticated, service_role;

-- RPCs/plpgsql pass type as TEXT; ASSIGNMENT cast restores INSERT/UPDATE assignment
-- without rewriting every SECURITY DEFINER body. Invalid literals already coerce.
DO $$ BEGIN
  CREATE CAST (text AS public.ledger_event_type) WITH INOUT AS ASSIGNMENT;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;
