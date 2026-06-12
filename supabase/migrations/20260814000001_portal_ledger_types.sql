-- =============================================================================
-- Migration: Portal Ledger Types — Widen CHECK for Dispute Portal facts
-- Purpose:   Adds 3 new ledger fact types for the Forensic Dispute Portal (5.3):
--            DISPUTE_PORTAL_TOKEN_GENERATED, _ACCESSED, _REVOKED.
--
-- Pattern:   H1-safe: ADD NOT VALID (superset) → VALIDATE → DROP old → RENAME.
--            Never DROP-first — no constraint-free window.
--
-- Invariants: INV-3 (append-only ledger), INV-DB (zero-downtime).
-- Depends on: 20260813000007 (chk_ledger_type is the current constraint name).
-- =============================================================================

-- Step 1: Add the superset constraint as NOT VALID (no table scan, instant).
ALTER TABLE public.sla_audit_ledger_v2
  ADD CONSTRAINT chk_ledger_type_v3 CHECK (type IN (
    -- Original (pre-10.6)
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
    'DUAL_CONTROL_THRESHOLD_CHANGED',
    -- Phase 10.6
    'DISPUTE_EVIDENCE_ATTACHED','DISPUTE_SLA_BREACHED','EVIDENCE_HASH_MISMATCH',
    -- Phase 10.6 — Item 5.3: Forensic Dispute Portal
    'DISPUTE_PORTAL_TOKEN_GENERATED','DISPUTE_PORTAL_TOKEN_ACCESSED','DISPUTE_PORTAL_TOKEN_REVOKED'
  )) NOT VALID;

-- Step 2: Validate (scans existing rows, but doesn't lock writes — ShareUpdateExclusiveLock).
ALTER TABLE public.sla_audit_ledger_v2 VALIDATE CONSTRAINT chk_ledger_type_v3;

-- Step 3: Drop the old constraint (safe — v3 is already validated and enforcing).
ALTER TABLE public.sla_audit_ledger_v2 DROP CONSTRAINT IF EXISTS chk_ledger_type; -- INV-DB: zero-downtime-verified

-- Step 4: Restore canonical name for stable identity across widenings.
ALTER TABLE public.sla_audit_ledger_v2 RENAME CONSTRAINT chk_ledger_type_v3 TO chk_ledger_type;
