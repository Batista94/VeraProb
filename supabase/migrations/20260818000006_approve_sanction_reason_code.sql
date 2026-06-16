-- Migration: approve_sanction — capture optional reviewer reason code + note
--
-- Why: the auditor verdict UI (SentencePanelModal) collects a taxonomy reason
-- code and an optional free-text note when an auditor seals a pending verdict
-- ("CONFIRMAR INFRAÇÃO"). The prior approve_sanction had no parameter to carry
-- it, so the auditor's rationale was silently discarded — a forensic gap
-- (INV-21 / INV-23 verdict explainability). This threads both into the canonical
-- terminal VERDICT_SEALED ledger fact (INV-3 append-only).
--
-- Base: this REPLACES the dual-control build of approve_sanction
-- (20260812000003) — the peer-review fork is preserved verbatim; only the
-- terminal seal path gains reason_code / reviewer_reason. CREATE OR REPLACE
-- cannot add parameters, so the 5-arg overload is dropped and recreated with two
-- trailing optional params (DEFAULT NULL); existing 5-arg callers / committed
-- pgTAP keep resolving (defaults fill the gap; body no-ops on NULL).
--
-- reason_code is OPTIONAL for approval (sealing affirms the engine's computed
-- verdict) but VALIDATED against the closed dispute_reason_codes taxonomy when
-- supplied (zero-trust). An unknown/inactive code fails opaque with
-- insufficient_privilege — identical to every other guard, so the function is
-- not an oracle for taxonomy membership (INV-26). The high-value path forks to
-- peer review unchanged (the first auditor's code is validated, then the second
-- auditor supplies the binding code at confirm time).

DROP FUNCTION IF EXISTS public.approve_sanction(UUID, UUID, UUID, TEXT, TIMESTAMPTZ);

CREATE FUNCTION public.approve_sanction(
  p_organization_id     UUID,
  p_queue_entry_id      UUID,
  p_reviewed_by_user_id UUID,
  p_actor_email         TEXT,
  p_occurred_at_utc     TIMESTAMPTZ,
  p_reason_code         TEXT DEFAULT NULL,
  p_reviewer_reason     TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_jwt_org         TEXT;
  v_jwt_role        TEXT;
  v_user            UUID;
  v_queue           public.sanction_review_queue;
  v_ledger_id       UUID;
  v_fine            BIGINT;
  v_threshold       BIGINT;
  v_ttl             INT;
  v_reason_code     TEXT;
  v_reviewer_reason TEXT;
BEGIN
  v_jwt_org := auth.jwt() -> 'app_metadata' ->> 'org_id';
  IF v_jwt_org IS NULL OR v_jwt_org::uuid <> p_organization_id THEN
    RAISE EXCEPTION 'Sanction approval rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  v_jwt_role := auth.jwt() -> 'app_metadata' ->> 'role';
  IF v_jwt_role IS NULL OR v_jwt_role NOT IN ('TENANT_ADMIN', 'AUDITOR') THEN
    RAISE EXCEPTION 'Sanction approval rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- ── Optional reviewer reason code: validated only when supplied ──────────
  v_reason_code := NULLIF(btrim(p_reason_code), '');
  IF v_reason_code IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM public.dispute_reason_codes
                      WHERE code = v_reason_code
                        AND is_active = TRUE
                        AND organization_id IS NULL) THEN
    RAISE EXCEPTION 'Sanction approval rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  v_reviewer_reason := NULLIF(btrim(p_reviewer_reason), '');

  v_user := (auth.jwt() ->> 'sub')::uuid;
  IF v_user IS NULL OR v_user <> p_reviewed_by_user_id THEN
    RAISE EXCEPTION 'Sanction approval rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_queue
    FROM public.sanction_review_queue
   WHERE id = p_queue_entry_id AND organization_id = p_organization_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Sanction approval rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_queue.status <> 'pending' THEN
    RAISE EXCEPTION 'This sanction has already been reviewed by another auditor.'
      USING ERRCODE = 'P0001', DETAIL = 'IdempotencyProcessingException';
  END IF;

  -- ── Dual-control fork (INV-15: fine read from the sealed evidence) ──────────
  -- Preserved verbatim from 20260812000003. The binding reason code for a
  -- high-value verdict is supplied by the SECOND auditor at confirm time.
  v_fine := (v_queue.verdict_evidence ->> 'fine_cents')::bigint;
  v_threshold := public._resolve_dual_control_threshold(p_organization_id, v_queue.contract_id);
  v_ttl := public._resolve_dual_control_ttl(p_organization_id);

  IF v_threshold IS NOT NULL AND v_fine > v_threshold THEN
    UPDATE public.sanction_review_queue
       SET status = 'pending_peer_review',
           first_reviewer_id = v_user,
           first_reviewed_at = p_occurred_at_utc,
           peer_review_origin_status = 'pending',
           peer_review_proposed_action = 'APPROVE',
           peer_review_reason = NULL,
           peer_review_expires_at = p_occurred_at_utc + make_interval(hours => v_ttl)
     WHERE id = p_queue_entry_id AND organization_id = p_organization_id;

    v_ledger_id := public._append_peer_review_requested(
      p_organization_id, v_queue, v_user, p_actor_email, 'APPROVE',
      NULL, v_fine, v_threshold, p_occurred_at_utc);

    RETURN jsonb_build_object('ledger_entry_id', v_ledger_id, 'status', 'pending_peer_review');
  END IF;

  -- ── Terminal path (fine <= threshold OR dual-control off) ───────────────────
  -- reason_code / reviewer_reason recorded here (NULL when sealed without one).
  INSERT INTO public.sla_audit_ledger_v2
    (organization_id, type, operator_id, set_id, contract_id, plan_version, payload, occurred_at_utc)
  VALUES (
    p_organization_id, 'VERDICT_SEALED', v_user::text, v_queue.set_id,
    v_queue.contract_id::uuid, 0,
    jsonb_build_object(
      'queue_entry_id', p_queue_entry_id,
      'approved_by_user_id', v_user,
      'actor_email', p_actor_email,
      'reason_code', v_reason_code,
      'reviewer_reason', v_reviewer_reason,
      'verdict_evidence', v_queue.verdict_evidence
    ),
    p_occurred_at_utc
  )
  RETURNING id INTO v_ledger_id;

  UPDATE public.sanction_review_queue
     SET status = 'applied', reviewed_at = p_occurred_at_utc, reviewed_by = v_user
   WHERE id = p_queue_entry_id AND organization_id = p_organization_id;

  RETURN jsonb_build_object('ledger_entry_id', v_ledger_id, 'status', 'applied');
END;
$$;

-- ── Grants: mirror the original posture exactly ──────────────────────────────
-- authenticated only; anon + service_role denied. A service_role token carries
-- no app_metadata.org_id and must never bypass the Data API (INV-22).
REVOKE ALL ON FUNCTION
  public.approve_sanction(UUID, UUID, UUID, TEXT, TIMESTAMPTZ, TEXT, TEXT)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION
  public.approve_sanction(UUID, UUID, UUID, TEXT, TIMESTAMPTZ, TEXT, TEXT)
  TO authenticated;
