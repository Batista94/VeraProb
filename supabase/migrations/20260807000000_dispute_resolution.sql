-- Migration: Dispute Resolution Schema Adjustments (Pacote 5)
-- Purpose: Introduce partial index on Completed tab and CHECK constraint on ledger.type.
-- Invariants: INV-DB (Zero-Downtime), INV-2 (RLS & Isolation).

-- 1. Create partial index for Completed tab (applied/rejected)
CREATE INDEX IF NOT EXISTS idx_srq_org_status_concluded_at
  ON public.sanction_review_queue (organization_id, created_at DESC)
  WHERE status IN ('applied', 'rejected');

-- 2. Add CHECK constraint on public.sla_audit_ledger_v2.type safely (idempotent DO block)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'chk_ledger_type' AND conrelid = 'public.sla_audit_ledger_v2'::regclass
  ) THEN
    ALTER TABLE public.sla_audit_ledger_v2
      ADD CONSTRAINT chk_ledger_type CHECK (type IN (
        'EXECUTION_BOUND',
        'NO_SHOW_DECLARED',
        'EVIDENCE_GAP_DECLARED',
        'PLAN_DECLARED',
        'OCCURRENCE_REGISTERED',
        'TRIP_INTERRUPTED',
        'TRIP_CANCELLED',
        'CONTRACT_CREATED',
        'CONTRACT_ACTIVATED',
        'CONTRACT_CLOSED',
        'CONTRACT_SUBMITTED_FOR_APPROVAL',
        'CONTRACT_ACCEPTED_BY_CONTRACTOR',
        'SANCTION_RECOMMENDED',
        'VERDICT_SEALED',
        'VERDICT_REFUSED',
        'SANCTION_DISPUTED',
        'DISPUTE_ACCEPTED',
        'DISPUTE_OVERTURNED',
        'DISPUTE_RETRACTED',
        'JUSTIFICATION_SUBMITTED',
        'JUSTIFICATION_APPROVED',
        'JUSTIFICATION_REJECTED',
        'SLA_JUSTIFICATION_SUBMITTED',
        'SLA_JUSTIFICATION_EXPIRED',
        'TRANSIT_STARTED',
        'COMPLETED_WITH_GAPS',
        'EXECUTION_INHIBITED',
        'UNKNOWN_EVENT',
        'MAX_TOLERANCE_DELAY',
        'MAX_EVIDENCE_GAP',
        'MIN_GEOFENCE_COVERAGE',
        'NO_SHOW_PENALTY'
      )) NOT VALID; -- INV-DB: zero-downtime-verified (avoids validation scan on historical rows)
  END IF;
END $$;
