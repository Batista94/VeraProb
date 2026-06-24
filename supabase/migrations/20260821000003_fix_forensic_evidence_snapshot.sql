-- =============================================================================
-- Migration: fix_forensic_evidence_snapshot — Issue 1
-- Purpose:   Updates verify_forensic_evidence and verify_forensic_evidence_by_queue
--            to return the full canonical row (to_jsonb(v_row)) as the 'snapshot'
--            key, rather than just the inner JSON snapshot field. This closes a
--            TOCTOU vulnerability (INV-9) where the application had to re-query
--            the row to instantiate the ForensicEvidenceSnapshot domain model.
--
-- Pattern:   CREATE OR REPLACE FUNCTION (Zero-downtime, INV-DB).
--
-- Council: Architect ✅ · Senior ✅ · QA-Security ✅ · Business ✅ · Lead ✅
-- Invariants: INV-9, INV-26, INV-22.
-- Depends on: 20260801010000_forensic_evidence_vault.sql, 20260819000002_forensic_evidence_by_queue.sql
-- =============================================================================

SET client_min_messages TO 'WARNING';

-- ── 1. verify_forensic_evidence (by ledger_entry_id) ─────────────────────────

CREATE OR REPLACE FUNCTION public.verify_forensic_evidence(
  p_organization_id UUID,
  p_ledger_entry_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, extensions
AS $$
DECLARE
  v_row      public.forensic_evidence_snapshots;
  v_computed TEXT;
BEGIN
  SELECT * INTO v_row
    FROM public.forensic_evidence_snapshots
   WHERE organization_id = p_organization_id
     AND ledger_entry_id = p_ledger_entry_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Snapshot not found for verdict % (Req 8/INV-26)', p_ledger_entry_id
      USING ERRCODE = 'P0002';
  END IF;

  v_computed := encode(extensions.digest(public.jsonb_canonical_text(v_row.snapshot), 'sha256'), 'hex');

  RETURN jsonb_build_object(
    'ledger_entry_id', v_row.ledger_entry_id,
    'stored_hash',     v_row.integrity_hash,
    'computed_hash',   v_computed,
    'status',          CASE WHEN v_computed = v_row.integrity_hash
                            THEN 'authentic' ELSE 'tampered' END,
    'snapshot',        to_jsonb(v_row)
  );
END;
$$;

-- ── 2. verify_forensic_evidence_by_queue ─────────────────────────────────────

CREATE OR REPLACE FUNCTION public.verify_forensic_evidence_by_queue(
  p_organization_id UUID,
  p_queue_entry_id  UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, extensions
AS $$
DECLARE
  v_row      public.forensic_evidence_snapshots;
  v_computed TEXT;
BEGIN
  SELECT * INTO v_row
    FROM public.forensic_evidence_snapshots
   WHERE organization_id = p_organization_id
     AND queue_entry_id  = p_queue_entry_id
   ORDER BY sealed_at_utc DESC
   LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Snapshot not found for queue entry % (INV-26)', p_queue_entry_id
      USING ERRCODE = 'P0002';
  END IF;

  v_computed := encode(
    extensions.digest(public.jsonb_canonical_text(v_row.snapshot), 'sha256'),
    'hex'
  );

  RETURN jsonb_build_object(
    'ledger_entry_id', v_row.ledger_entry_id,
    'stored_hash',     v_row.integrity_hash,
    'computed_hash',   v_computed,
    'status',          CASE WHEN v_computed = v_row.integrity_hash
                            THEN 'authentic' ELSE 'tampered' END,
    'snapshot',        to_jsonb(v_row)
  );
END;
$$;

RESET client_min_messages;
