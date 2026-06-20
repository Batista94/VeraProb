-- =============================================================================
-- Migration: read_dispute_portal — "SLA encerrado" sealed-state response
-- Purpose:   Complete the Revogação de Acesso Externo. When a verdict is sealed
--            internally (20260823000002), the outstanding portal token is revoked
--            in the same txn. Previously read_dispute_portal collapsed revoked →
--            generic 'Portal access denied.', which is indistinguishable from a
--            forged/expired token and gives the carrier no closure signal.
--
--            New behaviour: if the token EXISTS and is NOT expired but IS revoked
--            AND the queue entry reached a TERMINAL verdict
--            (applied | rejected | acknowledged), return a closed snapshot:
--              { "closed": true, "closed_reason": "JUDGED_INTERNALLY",
--                "dispute_summary": { "status": <terminal> } }
--            The frontend renders "SLA encerrado. Sanção julgada internamente."
--            and hides upload/submit — no phantom attachment can be attempted.
--
-- Anti-oracle (INV-26): the closed branch is reachable ONLY by a caller that
--   already proved possession of a real, non-expired token (NOT FOUND and expired
--   still collapse to the generic deny). Revealing terminal closure to that holder
--   is not enumeration — it is information the legitimate party is owed. A token
--   revoked for any NON-terminal reason (e.g. admin revocation while still
--   disputed) keeps the generic deny.
--
-- Side-channel: the pre-SELECT advisory lock is preserved on every path. The
--   closed branch performs the SAME token load; no access_count bump and no
--   ledger write (the token is dead) — consistent with the deny path's no-op.
--
-- pr_scanner: ignore-regression — CREATE OR REPLACE on existing signature; no
--   merged migration modified. Council-approved (Architect · Senior · QA-Security).
-- Invariants: INV-1, INV-3, INV-6, INV-9, INV-22, INV-26.
-- =============================================================================

SET client_min_messages TO 'WARNING';

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
  PERFORM pg_advisory_xact_lock(hashtextextended(p_token::text, 0));

  -- ── Load + lock token row ──────────────────────────────────────────────────
  SELECT * INTO v_token_row
    FROM public.dispute_portal_tokens
   WHERE token = p_token
   FOR UPDATE;

  -- INV-26: forged / unknown token → generic deny.
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Portal access denied.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Expired? → generic deny (no closure signal; token may never have been valid).
  IF v_now > v_token_row.expires_at_utc THEN
    RAISE EXCEPTION 'Portal access denied.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- ── Revoked? Distinguish internal-verdict closure from a bare deny ──────────
  IF v_token_row.revoked_at_utc IS NOT NULL THEN
    SELECT * INTO v_queue
      FROM public.sanction_review_queue
     WHERE id = v_token_row.queue_entry_id
       AND organization_id = v_token_row.organization_id;

    -- Token holder proved possession of a real, non-expired token AND the
    -- sanction is terminally judged → return the sealed closure (no oracle).
    IF FOUND AND v_queue.status IN ('applied', 'rejected', 'acknowledged') THEN
      RETURN jsonb_build_object(
        'closed', true,
        'closed_reason', 'JUDGED_INTERNALLY',
        'dispute_summary', jsonb_build_object('status', v_queue.status)
      );
    END IF;

    -- Revoked for any other reason (e.g. admin revocation while still disputed)
    -- → preserve the generic deny.
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
    RAISE EXCEPTION 'Portal access denied.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- ── Build evidence list (whitelist projection: QA-Sec T5) ──────────────────
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
  v_hash := encode(digest(v_snapshot::text, 'sha256'), 'hex');
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

RESET client_min_messages;
