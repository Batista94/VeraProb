-- =============================================================================
-- Migration: verify_evidence_hash RPC — Server-Side SHA-256 Re-Verification (B2)
-- Purpose:   ADD-2 close. The edge function `verify-evidence-hash` downloads the
--            stored bytes (service_role), recomputes SHA-256, and calls this RPC
--            to COMPARE against the sealed `sha256_hash` and persist the verdict.
--            We never recompute the digest inside PL/pgSQL over <=10MB blobs
--            (statement timeout) — the RPC only compares and seals state.
--
--            On mismatch it appends an immutable `EVIDENCE_HASH_MISMATCH` fact
--            (declared hash != stored bytes = INV-9 violation attempt) and flips
--            `verification_status='MISMATCH'`, which `resolve_dispute` (008, B2)
--            hard-blocks. On match it flips to `VERIFIED`.
--
-- Invariants: INV-1, INV-3 (append-only fact), INV-9, INV-22, INV-26.
-- Depends on: 007 (ledger CHECK widened to allow EVIDENCE_HASH_MISMATCH),
--             001 (dispute_evidence_attachments + non-sealed verification cols).
-- Trust:      service_role only (the edge function is trusted infra). Tenant scope
--             is enforced by the (id, organization_id) row predicate, NOT a JWT
--             claim — there is no authenticated caller here.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.verify_evidence_hash(
  p_attachment_id   UUID,
  p_organization_id UUID,
  p_computed_hash   TEXT,
  p_verified_at     TIMESTAMPTZ
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_row    public.dispute_evidence_attachments;
  v_set_id TEXT;
  v_status TEXT;
BEGIN
  SELECT * INTO v_row FROM public.dispute_evidence_attachments
   WHERE id = p_attachment_id AND organization_id = p_organization_id
   FOR UPDATE;
  IF NOT FOUND THEN
    -- Anti-oracle (INV-26): wrong-org and not-found are indistinguishable.
    RAISE EXCEPTION 'Verification rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_row.sha256_hash = lower(p_computed_hash) THEN
    v_status := 'VERIFIED';
  ELSE
    v_status := 'MISMATCH';
    -- set_id is carried by the queue entry, not the attachment row.
    SELECT set_id INTO v_set_id FROM public.sanction_review_queue
     WHERE id = v_row.queue_entry_id AND organization_id = p_organization_id;

    -- Forensic fact: declared hash != stored bytes (INV-9 violation attempt).
    -- contract_id NULL is intentional — this is an integrity fact, not financial.
    INSERT INTO public.sla_audit_ledger_v2
      (organization_id, type, operator_id, set_id, contract_id, plan_version, payload, occurred_at_utc)
    VALUES (
      p_organization_id, 'EVIDENCE_HASH_MISMATCH', 'SYSTEM',
      v_set_id, NULL, 0,
      jsonb_build_object(
        'queue_entry_id', v_row.queue_entry_id,
        'attachment_id',  v_row.id,
        'declared_hash',  v_row.sha256_hash,
        'computed_hash',  lower(p_computed_hash)
      ),
      p_verified_at
    );
  END IF;

  -- verification_status / hash_verified_at are NOT sealed fields (the
  -- prevent_dea_immutable_mutation trigger explicitly allows these two).
  UPDATE public.dispute_evidence_attachments
     SET verification_status = v_status, hash_verified_at = p_verified_at
   WHERE id = p_attachment_id AND organization_id = p_organization_id;

  RETURN v_status;
END;
$$;

-- ── Grants: service_role ONLY (trusted edge function path) ────────────────────
-- No authenticated/anon EXECUTE: clients never re-verify their own evidence.
REVOKE ALL ON FUNCTION public.verify_evidence_hash(UUID, UUID, TEXT, TIMESTAMPTZ)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.verify_evidence_hash(UUID, UUID, TEXT, TIMESTAMPTZ)
  TO service_role;
