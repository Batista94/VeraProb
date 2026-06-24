-- Migration: index + verify_forensic_evidence_by_queue RPC
--
-- Why: forensic_evidence_snapshots.queue_entry_id was added by the previous
-- migration but has no covering index. The Forensic Evidence Modal looks up a
-- snapshot by queue entry on every card open — without an index this is a
-- full org-partition table scan. This migration:
--   (a) Creates a partial index on (organization_id, queue_entry_id) filtered
--       WHERE queue_entry_id IS NOT NULL, sorted sealed_at_utc DESC so the
--       LIMIT 1 query uses an index scan.
--   (b) Creates verify_forensic_evidence_by_queue(p_organization_id, p_queue_entry_id)
--       — SECURITY INVOKER (RLS-scoped), mirrors verify_forensic_evidence return
--       shape ({ledger_entry_id, stored_hash, computed_hash, status, snapshot}).
--       Selects the most recent snapshot for the queue entry (ORDER BY sealed_at_utc
--       DESC LIMIT 1). Raises P0002 (consistent with verify_forensic_evidence) if
--       no snapshot found — maps to ResourceNotFoundException in the Dart repo.
--
-- Invariants: INV-26 (P0002 = 404-parity), INV-22 (SECURITY INVOKER = RLS-scoped),
-- INV-9 (SHA-256 recomputed on read), INV-12 (index advisory).

SET client_min_messages TO 'WARNING';

-- ── (a) Queue-entry lookup index ─────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_fes_org_queue_entry
  ON public.forensic_evidence_snapshots (organization_id, queue_entry_id, sealed_at_utc DESC)
  WHERE queue_entry_id IS NOT NULL;

-- ── (b) verify_forensic_evidence_by_queue ────────────────────────────────────
-- SECURITY INVOKER: RLS on forensic_evidence_snapshots scopes the SELECT to the
-- caller's own org via app_metadata.org_id. Cross-tenant lookup returns NOT FOUND
-- → P0002 (INV-26 404-parity, identical to verify_forensic_evidence).

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
    'snapshot',        v_row.snapshot
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.verify_forensic_evidence_by_queue(UUID, UUID)
  TO authenticated, service_role;
