-- =============================================================================
-- Migration: add structured reason-code columns to sanction_review_queue
-- Threads the closed taxonomy (dispute_reason_codes) through the dispute
-- lifecycle: rejection, resolution, and the dual-control peer-review hold.
--
-- B6: the FK target `code` is industry-agnostic; vertical wording stays in the
--     catalogue's label_pt/label_en, never here.
-- H3: backfill is batched (bounded 1000-row UPDATE loop), never one unbounded
--     UPDATE that would lock the whole table.
-- Invariants: INV-1, INV-6, INV-DB (additive nullable columns = zero-downtime).
-- =============================================================================

-- ── A: Add columns (nullable FK → closed catalogue) ──────────────────────────
ALTER TABLE public.sanction_review_queue
  ADD COLUMN IF NOT EXISTS rejection_reason_code TEXT
    REFERENCES public.dispute_reason_codes(code);
ALTER TABLE public.sanction_review_queue
  ADD COLUMN IF NOT EXISTS resolution_reason_code TEXT
    REFERENCES public.dispute_reason_codes(code);
-- Structured code carried through the dual-control peer-review hold (Senior F5).
ALTER TABLE public.sanction_review_queue
  ADD COLUMN IF NOT EXISTS peer_review_reason_code TEXT
    REFERENCES public.dispute_reason_codes(code);

-- ── B: H3 batched backfill (bounded UPDATE, no table-wide lock) ───────────────
-- NOTE: sanction_review_queue DOES carry an immutability trigger
-- (prevent_srq_immutable_mutation). It guards only org_id / ledger_entry_id /
-- set_id / contract_id / verdict_evidence / created_at / vehicle_plate /
-- operator_name. The new *_reason_code columns are NOT in that guard set, so
-- this backfill (and the later resolution RPCs that set them) is not blocked.
DO $$
DECLARE v_rows INT;
BEGIN
  LOOP
    UPDATE public.sanction_review_queue
       SET rejection_reason_code = 'LEGACY_UNCLASSIFIED'
     WHERE id IN (
       SELECT id FROM public.sanction_review_queue
        WHERE rejection_reason IS NOT NULL AND rejection_reason_code IS NULL
        LIMIT 1000
     );
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    EXIT WHEN v_rows = 0;
  END LOOP;
END $$;

COMMENT ON COLUMN public.sanction_review_queue.rejection_reason_code IS
  'Structured rejection reason (FK dispute_reason_codes). Required for reject/dispute_accept.';
COMMENT ON COLUMN public.sanction_review_queue.resolution_reason_code IS
  'Structured resolution reason (FK dispute_reason_codes). Required for accept/overturn.';
COMMENT ON COLUMN public.sanction_review_queue.peer_review_reason_code IS
  'Structured reason held during pending_peer_review; embedded by confirm_peer_review.';
