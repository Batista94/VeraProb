-- Suppress DROP CONSTRAINT IF EXISTS NOTICEs on fresh reset.
SET client_min_messages TO 'WARNING';

-- =============================================================================
-- Migration: Dual-Control (Four-Eyes) — Schema (Phase 10.5, Item 2)
-- Purpose:   Add the data model that lets a high-value sanction verdict require
--            a SECOND, DISTINCT auditor before it becomes terminal. Closes the
--            internal-collusion vector where one auditor alone enforces or waives
--            a high-value penalty to favour/punish a carrier.
--
--            This migration is SCHEMA ONLY (additive columns + widened CHECKs).
--            The transactional state machine + the mathematical reviewer2 != reviewer1
--            guarantee live in 20260812000003_dual_control_rpcs.sql.
--
-- pr_scanner: ignore-regression — additive only (ADD COLUMN, widen CHECK via
--   drop+re-add with the SAME superset of values, no row ever invalidated). No
--   merged migration modified. Council-approved.
--
-- Invariants:
--   INV-DB  Zero-downtime: every ADD COLUMN is nullable or NOT NULL WITH DEFAULT
--           (no table rewrite); CHECK widening is a strict superset (NOT VALID →
--           VALIDATE never fails on historical rows).
--   INV-4   Money is BIGINT cents (dual_control_threshold_cents).
--   INV-6   TIMESTAMPTZ for every datetime column.
--   INV-2   No new tables → existing RLS on sanction_review_queue / organizations
--           / contracts continues to govern; SECURITY DEFINER RPCs re-assert org.
-- =============================================================================

-- ── 1. Threshold home: org baseline + per-contract override ───────────────────
-- NULL threshold  = dual-control DISABLED for that scope.
-- Resolution at verdict time: COALESCE(contract.threshold, org.threshold).
ALTER TABLE public.organizations
  ADD COLUMN IF NOT EXISTS dual_control_threshold_cents BIGINT;
ALTER TABLE public.organizations
  ADD COLUMN IF NOT EXISTS dual_control_ttl_hours INT NOT NULL DEFAULT 48;

ALTER TABLE public.contracts
  ADD COLUMN IF NOT EXISTS dual_control_threshold_cents BIGINT; -- NULL = inherit org

COMMENT ON COLUMN public.organizations.dual_control_threshold_cents IS
  'Four-eyes threshold (BIGINT cents). NULL = dual-control OFF for this tenant. '
  'A verdict whose verdict_evidence.fine_cents > threshold requires a second '
  'distinct auditor (INV-4).';
COMMENT ON COLUMN public.organizations.dual_control_ttl_hours IS
  'Hours a pending_peer_review item may wait before expire_stale_peer_reviews() '
  'reverts it to its origin status (anti-starvation / availability).';
COMMENT ON COLUMN public.contracts.dual_control_threshold_cents IS
  'Per-contract override of the org dual-control threshold (BIGINT cents). '
  'NULL = inherit organizations.dual_control_threshold_cents.';

-- ── 2. New queue status: pending_peer_review ──────────────────────────────────
-- Widen chk_srq_status to a strict superset. Drop + re-add (a CHECK cannot be
-- altered in place). Widening never invalidates an existing row; NOT VALID →
-- VALIDATE keeps it zero-downtime.
ALTER TABLE public.sanction_review_queue DROP CONSTRAINT IF EXISTS chk_srq_status;
ALTER TABLE public.sanction_review_queue
  ADD CONSTRAINT chk_srq_status
  CHECK (status IN ('pending', 'applied', 'rejected', 'disputed', 'pending_peer_review'))
  NOT VALID;
ALTER TABLE public.sanction_review_queue VALIDATE CONSTRAINT chk_srq_status;

-- ── 3. Peer-review control columns (all mutable — outside the immutability set) ─
-- prevent_srq_immutable_mutation() guards only org_id/ledger_entry_id/set_id/
-- contract_id/verdict_evidence/created_at, so these new columns are freely
-- UPDATE-able by the RPCs.
ALTER TABLE public.sanction_review_queue
  ADD COLUMN IF NOT EXISTS first_reviewer_id UUID;
ALTER TABLE public.sanction_review_queue
  ADD COLUMN IF NOT EXISTS first_reviewed_at TIMESTAMPTZ;
ALTER TABLE public.sanction_review_queue
  ADD COLUMN IF NOT EXISTS peer_review_origin_status TEXT;
ALTER TABLE public.sanction_review_queue
  ADD COLUMN IF NOT EXISTS peer_review_proposed_action TEXT;
ALTER TABLE public.sanction_review_queue
  ADD COLUMN IF NOT EXISTS peer_review_reason TEXT;
ALTER TABLE public.sanction_review_queue
  ADD COLUMN IF NOT EXISTS peer_review_expires_at TIMESTAMPTZ;

-- Domain of the proposed action carried while a verdict waits for the 2nd auditor.
ALTER TABLE public.sanction_review_queue
  DROP CONSTRAINT IF EXISTS chk_srq_peer_action;
ALTER TABLE public.sanction_review_queue
  ADD CONSTRAINT chk_srq_peer_action
  CHECK (
    peer_review_proposed_action IS NULL
    OR peer_review_proposed_action IN ('APPROVE', 'REJECT', 'OVERTURN', 'DISPUTE_ACCEPT')
  ) NOT VALID;
ALTER TABLE public.sanction_review_queue VALIDATE CONSTRAINT chk_srq_peer_action;

COMMENT ON COLUMN public.sanction_review_queue.first_reviewer_id IS
  'JWT sub of the auditor who REQUESTED the high-value verdict. The peer RPC '
  'rejects a confirm whose JWT sub equals this value (reviewer2 != reviewer1).';
COMMENT ON COLUMN public.sanction_review_queue.peer_review_origin_status IS
  'Status to revert to on decline/expiry (pending for approve/reject origin, '
  'disputed for overturn/dispute-accept origin).';

-- Partial index for the auditor "Awaiting 2nd auditor" lane + the expiry sweep.
CREATE INDEX IF NOT EXISTS idx_srq_peer_review_pending
  ON public.sanction_review_queue (organization_id, peer_review_expires_at)
  WHERE status = 'pending_peer_review';

-- ── 4. Ledger fact types for the peer-review lifecycle + threshold audit ───────
-- Widen chk_ledger_type (currently NOT VALID) to a strict superset.
ALTER TABLE public.sla_audit_ledger_v2 DROP CONSTRAINT IF EXISTS chk_ledger_type;
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
    'NO_SHOW_PENALTY',
    -- Dual-control (Phase 10.5, Item 2)
    'PEER_REVIEW_REQUESTED',
    'PEER_REVIEW_DECLINED',
    'PEER_REVIEW_EXPIRED',
    'DUAL_CONTROL_THRESHOLD_CHANGED'
  )) NOT VALID; -- INV-DB: zero-downtime-verified (superset; no validation scan needed)
