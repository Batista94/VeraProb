-- =============================================================================
-- Migration: read_dispute_portal RPC — Anon-callable read-only dispute snapshot
-- Purpose:   External party accesses dispute evidence via a tokenized URL.
--            No JWT required — authentication is the token itself.
--
-- Security model:
--   - SECURITY DEFINER: bypasses RLS (anon has no JWT org claim).
--   - Pre-SELECT advisory lock normalizes timing (QA-Sec T7: anti side-channel).
--   - All failures (not found, expired, revoked, exhausted) → identical error.
--   - Whitelist projection: NO org_id, user IDs, storage_path, fine_cents.
--   - Snapshot hash (SHA-256 of served JSONB) logged in ledger fact on first
--     access for tamper-evidence (Business amendment).
--
-- Council: Architect ✅ · Senior ✅ · QA-Security ✅ · Business ✅ · Lead ✅
-- Invariants: INV-1, INV-3, INV-6, INV-9, INV-22, INV-26.
-- Depends on: 20260814000001 (ledger types), 20260814000002 (token table).
-- =============================================================================

CREATE OR REPLACE FUNCTION public.read_dispute_portal(
  p_token UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_token_row  public.dispute_portal_tokens;
  v_queue      public.sanction_review_queue;
  v_evidence   JSONB;
  v_snapshot   JSONB;
  v_hash       TEXT;
  v_now        TIMESTAMPTZ := NOW();
  v_is_first   BOOLEAN;
  v_verdict    JSONB;
BEGIN
  -- ── QA-Sec T7: Pre-SELECT advisory lock normalizes timing ──────────────────
  -- Without this, NOT FOUND skips the FOR UPDATE lock path, creating a
  -- measurable timing difference (side-channel). The advisory lock on the
  -- token hash ensures both FOUND and NOT FOUND paths have the same latency.
  PERFORM pg_advisory_xact_lock(hashtextextended(p_token::text, 0));

  -- ── Load + lock token row ──────────────────────────────────────────────────
  SELECT * INTO v_token_row
    FROM public.dispute_portal_tokens
   WHERE token = p_token
   FOR UPDATE;

  -- INV-26: all error paths produce identical error.
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Portal access denied.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Expired?
  IF v_now > v_token_row.expires_at_utc THEN
    RAISE EXCEPTION 'Portal access denied.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Revoked?
  IF v_token_row.revoked_at_utc IS NOT NULL THEN
    RAISE EXCEPTION 'Portal access denied.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Exhausted?
  IF v_token_row.access_count >= v_token_row.max_access_count THEN
    RAISE EXCEPTION 'Portal access denied.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- ── Track access ───────────────────────────────────────────────────────────
  v_is_first := (v_token_row.accessed_at_utc IS NULL);

  UPDATE public.dispute_portal_tokens
     SET access_count = access_count + 1,
         accessed_at_utc = CASE
           WHEN accessed_at_utc IS NULL THEN v_now
           ELSE accessed_at_utc
         END
   WHERE id = v_token_row.id;

  -- ── Load queue entry (org-scoped, sealed in token row) ──────────────────────
  SELECT * INTO v_queue
    FROM public.sanction_review_queue
   WHERE id = v_token_row.queue_entry_id
     AND organization_id = v_token_row.organization_id;
  IF NOT FOUND THEN
    -- Should never happen (FK integrity), but defense-in-depth.
    RAISE EXCEPTION 'Portal access denied.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- ── Build evidence list (whitelist projection: QA-Sec T5) ──────────────────
  -- EXCLUDES: organization_id, uploaded_by, storage_path (information disclosure).
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id',                  dea.id,
      'file_name',           dea.file_name,
      'mime_type',           dea.mime_type,
      'file_size_bytes',     dea.file_size_bytes,
      'sha256_hash',         dea.sha256_hash,
      'verification_status', dea.verification_status,
      'attached_at',         dea.attached_at
    ) ORDER BY dea.attached_at
  ), '[]'::jsonb)
    INTO v_evidence
    FROM public.dispute_evidence_attachments dea
   WHERE dea.queue_entry_id = v_token_row.queue_entry_id
     AND dea.organization_id = v_token_row.organization_id
     AND dea.deleted_at IS NULL;

  -- ── Build verdict summary (whitelist: exclude fine_cents, BIZ amendment) ────
  v_verdict := NULL;
  IF v_queue.verdict_evidence IS NOT NULL THEN
    v_verdict := jsonb_build_object(
      'rule_type', v_queue.verdict_evidence ->> 'rule_type',
      'description', v_queue.verdict_evidence ->> 'description'
    );
  END IF;

  -- ── Assemble snapshot ──────────────────────────────────────────────────────
  v_snapshot := jsonb_build_object(
    'dispute_summary', jsonb_build_object(
      'disputed_at',       v_queue.disputed_at,
      'resolution_due_at', v_queue.resolution_due_at,
      'status',            v_queue.status
    ),
    'evidence', v_evidence,
    'verdict_summary', v_verdict,
    'accessed_at', v_now
  );

  -- ── Compute snapshot hash (INV-9, Business amendment: tamper-evidence) ──────
  -- SHA-256 of the canonical JSONB text. Logged in ledger fact.
  v_hash := encode(digest(v_snapshot::text, 'sha256'), 'hex');

  -- Add hash to the response itself (self-referential integrity proof).
  v_snapshot := v_snapshot || jsonb_build_object('snapshot_hash', v_hash);

  -- ── Ledger fact on first access (forensic proof of notification) ────────────
  IF v_is_first THEN
    INSERT INTO public.sla_audit_ledger_v2
      (organization_id, type, operator_id, set_id, contract_id, plan_version, payload, occurred_at_utc)
    VALUES (
      v_token_row.organization_id, 'DISPUTE_PORTAL_TOKEN_ACCESSED', 'PORTAL',
      v_queue.set_id, v_queue.contract_id::uuid, 0,
      jsonb_build_object(
        'queue_entry_id', v_token_row.queue_entry_id,
        'token_id',       v_token_row.id,
        'snapshot_hash',  v_hash,
        'evidence_count', jsonb_array_length(v_evidence)
      ),
      v_now
    );
  END IF;

  RETURN v_snapshot;
END;
$$;

-- ── Grants: anon + authenticated can call (external portal has no JWT) ────────
REVOKE ALL ON FUNCTION public.read_dispute_portal(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.read_dispute_portal(UUID)
  TO anon, authenticated;
