-- =============================================================================
-- Migration: Dual-Control (Four-Eyes) — RPCs (Phase 10.5, Item 2)
-- Purpose:   Make a high-value verdict (fine_cents > resolved threshold) require
--            a SECOND, DISTINCT auditor. CREATE OR REPLACE the three verdict
--            entry points (approve_sanction / reject_sanction / resolve_dispute)
--            to fork into `pending_peer_review` instead of going terminal, and
--            add confirm / decline / expire RPCs that close the loop.
--
--            THE ANTI-FRAUD GUARANTEE is in confirm_peer_review: the confirming
--            auditor's identity is taken from the JWT `sub` (server-side, not a
--            client param) and is compared to first_reviewer_id (also captured
--            from the requester's JWT sub). Same person ⇒ same sub ⇒ rejected
--            with DualControlSelfApprovalException. One auditor can NEVER both
--            request and confirm a high-value verdict. reviewer2 != reviewer1 is
--            therefore a mathematical property, not a UI convention.
--
-- pr_scanner: ignore-regression — new additive migration (CREATE OR REPLACE fns
--   only; no merged migration modified). Mirrors the proven resolve_dispute /
--   approve_sanction templates. Council-approved.
--
-- Invariants:
--   INV-3   Ledger APPEND-ONLY — every state change appends a fact, never edits.
--   INV-1   org_id re-asserted from JWT (SECURITY DEFINER bypasses RLS).
--   INV-22  Tenant isolation — cross-tenant request/confirm/decline rejected.
--   INV-26  Anti-oracle — wrong-org AND not-found raise the SAME errcode (42501).
--   INV-10  Concurrent loser → P0001 + DETAIL IdempotencyProcessingException;
--           self-approval → P0001 + DETAIL DualControlSelfApprovalException.
--   INV-6   UTC — occurred_at supplied by caller (IDateTimeProvider.nowUtc()).
--   INV-15  Determinism — fine_cents read from the SEALED verdict_evidence on the
--           queue row (never recomputed), so a mid-flight threshold change cannot
--           alter an in-progress verdict.
--   INV-21  Verdict → snapshot — overturn confirm seals in the SAME transaction.
-- =============================================================================

-- ── approve_sanction (CREATE OR REPLACE — threshold fork added) ───────────────
CREATE OR REPLACE FUNCTION public.approve_sanction(
  p_organization_id     UUID,
  p_queue_entry_id      UUID,
  p_reviewed_by_user_id UUID,
  p_actor_email         TEXT,
  p_occurred_at_utc     TIMESTAMPTZ
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_jwt_org   TEXT;
  v_jwt_role  TEXT;
  v_user      UUID;
  v_queue     public.sanction_review_queue;
  v_ledger_id UUID;
  v_fine      BIGINT;
  v_threshold BIGINT;
  v_ttl       INT;
BEGIN
  v_jwt_org := auth.jwt() -> 'app_metadata' ->> 'org_id';
  IF v_jwt_org IS NULL OR v_jwt_org::uuid <> p_organization_id THEN
    RAISE EXCEPTION 'Sanction approval rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  v_jwt_role := auth.jwt() -> 'app_metadata' ->> 'role';
  IF v_jwt_role IS NULL OR v_jwt_role NOT IN ('TENANT_ADMIN', 'AUDITOR') THEN
    RAISE EXCEPTION 'Sanction approval rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

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
  INSERT INTO public.sla_audit_ledger_v2
    (organization_id, type, operator_id, set_id, contract_id, plan_version, payload, occurred_at_utc)
  VALUES (
    p_organization_id, 'VERDICT_SEALED', v_user::text, v_queue.set_id,
    v_queue.contract_id::uuid, 0,
    jsonb_build_object(
      'queue_entry_id', p_queue_entry_id,
      'approved_by_user_id', v_user,
      'actor_email', p_actor_email,
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

-- ── reject_sanction (CREATE OR REPLACE — threshold fork added) ────────────────
CREATE OR REPLACE FUNCTION public.reject_sanction(
  p_organization_id     UUID,
  p_queue_entry_id      UUID,
  p_reviewed_by_user_id UUID,
  p_actor_email         TEXT,
  p_rejection_reason    TEXT,
  p_occurred_at_utc     TIMESTAMPTZ
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_jwt_org   TEXT;
  v_jwt_role  TEXT;
  v_user      UUID;
  v_reason    TEXT;
  v_queue     public.sanction_review_queue;
  v_ledger_id UUID;
  v_fine      BIGINT;
  v_threshold BIGINT;
  v_ttl       INT;
BEGIN
  v_jwt_org := auth.jwt() -> 'app_metadata' ->> 'org_id';
  IF v_jwt_org IS NULL OR v_jwt_org::uuid <> p_organization_id THEN
    RAISE EXCEPTION 'Sanction rejection rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  v_jwt_role := auth.jwt() -> 'app_metadata' ->> 'role';
  IF v_jwt_role IS NULL OR v_jwt_role NOT IN ('TENANT_ADMIN', 'AUDITOR') THEN
    RAISE EXCEPTION 'Sanction rejection rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  v_reason := NULLIF(btrim(p_rejection_reason), '');
  IF v_reason IS NULL THEN
    RAISE EXCEPTION 'Sanction rejection rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  v_user := (auth.jwt() ->> 'sub')::uuid;
  IF v_user IS NULL OR v_user <> p_reviewed_by_user_id THEN
    RAISE EXCEPTION 'Sanction rejection rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_queue
    FROM public.sanction_review_queue
   WHERE id = p_queue_entry_id AND organization_id = p_organization_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Sanction rejection rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_queue.status <> 'pending' THEN
    RAISE EXCEPTION 'This sanction has already been reviewed by another auditor.'
      USING ERRCODE = 'P0001', DETAIL = 'IdempotencyProcessingException';
  END IF;

  -- ── Dual-control fork ───────────────────────────────────────────────────────
  v_fine := (v_queue.verdict_evidence ->> 'fine_cents')::bigint;
  v_threshold := public._resolve_dual_control_threshold(p_organization_id, v_queue.contract_id);
  v_ttl := public._resolve_dual_control_ttl(p_organization_id);

  IF v_threshold IS NOT NULL AND v_fine > v_threshold THEN
    UPDATE public.sanction_review_queue
       SET status = 'pending_peer_review',
           first_reviewer_id = v_user,
           first_reviewed_at = p_occurred_at_utc,
           peer_review_origin_status = 'pending',
           peer_review_proposed_action = 'REJECT',
           peer_review_reason = v_reason,
           peer_review_expires_at = p_occurred_at_utc + make_interval(hours => v_ttl)
     WHERE id = p_queue_entry_id AND organization_id = p_organization_id;

    v_ledger_id := public._append_peer_review_requested(
      p_organization_id, v_queue, v_user, p_actor_email, 'REJECT',
      v_reason, v_fine, v_threshold, p_occurred_at_utc);

    RETURN jsonb_build_object('ledger_entry_id', v_ledger_id, 'status', 'pending_peer_review');
  END IF;

  -- ── Terminal path ───────────────────────────────────────────────────────────
  INSERT INTO public.sla_audit_ledger_v2
    (organization_id, type, operator_id, set_id, contract_id, plan_version, payload, occurred_at_utc)
  VALUES (
    p_organization_id, 'VERDICT_REFUSED', v_user::text, v_queue.set_id,
    v_queue.contract_id::uuid, 0,
    jsonb_build_object(
      'queue_entry_id', p_queue_entry_id,
      'rejected_by_user_id', v_user,
      'actor_email', p_actor_email,
      'rejection_reason', v_reason,
      'verdict_evidence', v_queue.verdict_evidence
    ),
    p_occurred_at_utc
  )
  RETURNING id INTO v_ledger_id;

  UPDATE public.sanction_review_queue
     SET status = 'rejected', reviewed_at = p_occurred_at_utc,
         reviewed_by = v_user, rejection_reason = v_reason
   WHERE id = p_queue_entry_id AND organization_id = p_organization_id;

  RETURN jsonb_build_object('ledger_entry_id', v_ledger_id, 'status', 'rejected');
END;
$$;

-- ── resolve_dispute (CREATE OR REPLACE — threshold fork on enforce/waive) ─────
CREATE OR REPLACE FUNCTION public.resolve_dispute(
  p_organization_id     UUID,
  p_queue_entry_id      UUID,
  p_resolution          TEXT,
  p_resolution_reason   TEXT,
  p_resolved_by_user_id UUID,
  p_actor_email         TEXT,
  p_occurred_at_utc     TIMESTAMPTZ,
  p_idempotency_key     TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_jwt_org    TEXT;
  v_jwt_role   TEXT;
  v_user       UUID;
  v_queue      public.sanction_review_queue;
  v_new_status TEXT;
  v_ledger_id  UUID;
  v_snapshot   JSONB;
  v_fine       BIGINT;
  v_threshold  BIGINT;
  v_ttl        INT;
  v_action     TEXT;
BEGIN
  v_jwt_org := auth.jwt() -> 'app_metadata' ->> 'org_id';
  IF v_jwt_org IS NULL OR v_jwt_org::uuid <> p_organization_id THEN
    RAISE EXCEPTION 'Dispute resolution rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  v_jwt_role := auth.jwt() -> 'app_metadata' ->> 'role';
  IF v_jwt_role IS NULL OR v_jwt_role NOT IN ('TENANT_ADMIN', 'AUDITOR') THEN
    RAISE EXCEPTION 'Dispute resolution rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  v_new_status := CASE p_resolution
    WHEN 'DISPUTE_ACCEPTED'   THEN 'rejected'
    WHEN 'DISPUTE_OVERTURNED' THEN 'applied'
    WHEN 'DISPUTE_RETRACTED'  THEN 'pending'
    ELSE NULL
  END;
  IF v_new_status IS NULL THEN
    RAISE EXCEPTION 'Dispute resolution rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_queue
    FROM public.sanction_review_queue
   WHERE id = p_queue_entry_id AND organization_id = p_organization_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Dispute resolution rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_queue.status <> 'disputed' THEN
    RAISE EXCEPTION 'This dispute has already been resolved by another auditor.'
      USING ERRCODE = 'P0001', DETAIL = 'IdempotencyProcessingException';
  END IF;

  -- ── Dual-control fork: only the financially-effective resolutions ──────────
  -- (enforce / waive). DISPUTE_RETRACTED has no financial effect and is never
  -- gated. fine read from the sealed evidence (INV-15).
  IF p_resolution IN ('DISPUTE_OVERTURNED', 'DISPUTE_ACCEPTED') THEN
    v_fine := (v_queue.verdict_evidence ->> 'fine_cents')::bigint;
    v_threshold := public._resolve_dual_control_threshold(p_organization_id, v_queue.contract_id);
    v_ttl := public._resolve_dual_control_ttl(p_organization_id);

    IF v_threshold IS NOT NULL AND v_fine > v_threshold THEN
      -- Requester identity bound to JWT sub (anti-spoof) — the dual-control
      -- distinctness guarantee depends on this, not on p_resolved_by_user_id.
      v_user := (auth.jwt() ->> 'sub')::uuid;
      IF v_user IS NULL THEN
        RAISE EXCEPTION 'Dispute resolution rejected.' USING ERRCODE = 'insufficient_privilege';
      END IF;

      v_action := CASE p_resolution
        WHEN 'DISPUTE_OVERTURNED' THEN 'OVERTURN'
        ELSE 'DISPUTE_ACCEPT'
      END;

      UPDATE public.sanction_review_queue
         SET status = 'pending_peer_review',
             first_reviewer_id = v_user,
             first_reviewed_at = p_occurred_at_utc,
             peer_review_origin_status = 'disputed',
             peer_review_proposed_action = v_action,
             peer_review_reason = NULLIF(btrim(p_resolution_reason), ''),
             peer_review_expires_at = p_occurred_at_utc + make_interval(hours => v_ttl)
       WHERE id = p_queue_entry_id AND organization_id = p_organization_id;

      v_ledger_id := public._append_peer_review_requested(
        p_organization_id, v_queue, v_user, p_actor_email, v_action,
        NULLIF(btrim(p_resolution_reason), ''), v_fine, v_threshold, p_occurred_at_utc);

      RETURN jsonb_build_object(
        'ledger_entry_id', v_ledger_id, 'status', 'pending_peer_review', 'snapshot', NULL);
    END IF;
  END IF;

  -- ── Terminal path (existing behaviour) ──────────────────────────────────────
  INSERT INTO public.sla_audit_ledger_v2
    (organization_id, type, operator_id, set_id, contract_id, plan_version, payload, occurred_at_utc)
  VALUES (
    p_organization_id, p_resolution, p_resolved_by_user_id::text, v_queue.set_id,
    v_queue.contract_id::uuid, 0,
    jsonb_build_object(
      'queue_entry_id', p_queue_entry_id,
      'resolved_by_user_id', p_resolved_by_user_id,
      'actor_email', p_actor_email,
      'resolution_reason', NULLIF(btrim(p_resolution_reason), ''),
      'verdict_evidence', v_queue.verdict_evidence
    ),
    p_occurred_at_utc
  )
  RETURNING id INTO v_ledger_id;

  UPDATE public.sanction_review_queue
     SET status = v_new_status,
         reviewed_at = CASE WHEN p_resolution = 'DISPUTE_RETRACTED' THEN NULL ELSE p_occurred_at_utc END,
         reviewed_by = CASE WHEN p_resolution = 'DISPUTE_RETRACTED' THEN reviewed_by ELSE p_resolved_by_user_id END,
         rejection_reason = CASE
           WHEN p_resolution = 'DISPUTE_ACCEPTED'  THEN NULLIF(btrim(p_resolution_reason), '')
           WHEN p_resolution = 'DISPUTE_RETRACTED' THEN NULL
           ELSE rejection_reason
         END
   WHERE id = p_queue_entry_id AND organization_id = p_organization_id;

  IF p_resolution = 'DISPUTE_OVERTURNED' THEN
    v_snapshot := public.seal_dispute_resolution_snapshot(
      p_organization_id, v_ledger_id, v_queue.contract_id::uuid, v_queue.set_id,
      0, p_occurred_at_utc, p_resolved_by_user_id, p_idempotency_key);
  END IF;

  RETURN jsonb_build_object(
    'ledger_entry_id', v_ledger_id, 'status', v_new_status, 'snapshot', v_snapshot);
END;
$$;

-- ── Helper: resolve effective threshold (contract override > org baseline) ────
CREATE OR REPLACE FUNCTION public._resolve_dual_control_threshold(
  p_organization_id UUID,
  p_contract_id     TEXT
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_org_threshold      BIGINT;
  v_contract_threshold BIGINT;
  v_contract_uuid      UUID;
BEGIN
  SELECT dual_control_threshold_cents INTO v_org_threshold
    FROM public.organizations WHERE id = p_organization_id;

  BEGIN
    v_contract_uuid := p_contract_id::uuid;
  EXCEPTION WHEN others THEN
    v_contract_uuid := NULL;
  END;

  IF v_contract_uuid IS NOT NULL THEN
    SELECT dual_control_threshold_cents INTO v_contract_threshold
      FROM public.contracts
     WHERE id = v_contract_uuid AND organization_id = p_organization_id;
  END IF;

  RETURN COALESCE(v_contract_threshold, v_org_threshold);
END;
$$;

-- ── Helper: resolve org TTL (defaults 48h if column NULL) ─────────────────────
CREATE OR REPLACE FUNCTION public._resolve_dual_control_ttl(p_organization_id UUID)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_ttl INT;
BEGIN
  SELECT dual_control_ttl_hours INTO v_ttl
    FROM public.organizations WHERE id = p_organization_id;
  RETURN COALESCE(v_ttl, 48);
END;
$$;

-- ── Helper: append the PEER_REVIEW_REQUESTED fact (INV-3) ─────────────────────
CREATE OR REPLACE FUNCTION public._append_peer_review_requested(
  p_organization_id  UUID,
  p_queue            public.sanction_review_queue,
  p_first_reviewer   UUID,
  p_actor_email      TEXT,
  p_proposed_action  TEXT,
  p_reason           TEXT,
  p_fine_cents       BIGINT,
  p_threshold_cents  BIGINT,
  p_occurred_at_utc  TIMESTAMPTZ
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_ledger_id UUID;
BEGIN
  INSERT INTO public.sla_audit_ledger_v2
    (organization_id, type, operator_id, set_id, contract_id, plan_version, payload, occurred_at_utc)
  VALUES (
    p_organization_id, 'PEER_REVIEW_REQUESTED', p_first_reviewer::text,
    p_queue.set_id, p_queue.contract_id::uuid, 0,
    jsonb_build_object(
      'queue_entry_id', p_queue.id,
      'first_reviewer_id', p_first_reviewer,
      'actor_email', p_actor_email,
      'proposed_action', p_proposed_action,
      'peer_review_reason', p_reason,
      'fine_cents', p_fine_cents,
      'threshold_cents', p_threshold_cents,
      'verdict_evidence', p_queue.verdict_evidence
    ),
    p_occurred_at_utc
  )
  RETURNING id INTO v_ledger_id;
  RETURN v_ledger_id;
END;
$$;

-- ── confirm_peer_review — THE distinct-reviewer guarantee ─────────────────────
CREATE OR REPLACE FUNCTION public.confirm_peer_review(
  p_organization_id     UUID,
  p_queue_entry_id      UUID,
  p_reviewed_by_user_id UUID,
  p_actor_email         TEXT,
  p_occurred_at_utc     TIMESTAMPTZ,
  p_idempotency_key     TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_jwt_org      TEXT;
  v_jwt_role     TEXT;
  v_user         UUID;
  v_queue        public.sanction_review_queue;
  v_ledger_id    UUID;
  v_snapshot     JSONB;
  v_final_status TEXT;
  v_ledger_type  TEXT;
BEGIN
  v_jwt_org := auth.jwt() -> 'app_metadata' ->> 'org_id';
  IF v_jwt_org IS NULL OR v_jwt_org::uuid <> p_organization_id THEN
    RAISE EXCEPTION 'Peer review rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  v_jwt_role := auth.jwt() -> 'app_metadata' ->> 'role';
  IF v_jwt_role IS NULL OR v_jwt_role NOT IN ('TENANT_ADMIN', 'AUDITOR') THEN
    RAISE EXCEPTION 'Peer review rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  v_user := (auth.jwt() ->> 'sub')::uuid;
  IF v_user IS NULL OR v_user <> p_reviewed_by_user_id THEN
    RAISE EXCEPTION 'Peer review rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_queue
    FROM public.sanction_review_queue
   WHERE id = p_queue_entry_id AND organization_id = p_organization_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Peer review rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_queue.status <> 'pending_peer_review' THEN
    RAISE EXCEPTION 'This item is no longer awaiting a second auditor.'
      USING ERRCODE = 'P0001', DETAIL = 'IdempotencyProcessingException';
  END IF;

  -- ★ ANTI-FRAUD: the confirming auditor MUST differ from the requester. Both
  --   identities come from the JWT sub, so the same human can never satisfy both
  --   roles. This is the mathematical reviewer2 != reviewer1 guarantee.
  IF v_user = v_queue.first_reviewer_id THEN
    RAISE EXCEPTION 'The second auditor must differ from the auditor who requested this verdict.'
      USING ERRCODE = 'P0001', DETAIL = 'DualControlSelfApprovalException';
  END IF;

  -- ── Map the proposed action to its terminal verdict ─────────────────────────
  CASE v_queue.peer_review_proposed_action
    WHEN 'APPROVE'        THEN v_final_status := 'applied';   v_ledger_type := 'VERDICT_SEALED';
    WHEN 'OVERTURN'       THEN v_final_status := 'applied';   v_ledger_type := 'DISPUTE_OVERTURNED';
    WHEN 'REJECT'         THEN v_final_status := 'rejected';  v_ledger_type := 'VERDICT_REFUSED';
    WHEN 'DISPUTE_ACCEPT' THEN v_final_status := 'rejected';  v_ledger_type := 'DISPUTE_ACCEPTED';
    ELSE
      RAISE EXCEPTION 'Peer review rejected.' USING ERRCODE = 'insufficient_privilege';
  END CASE;

  -- ── Append the terminal fact with BOTH signatures (SOC2 dual-signature) ─────
  INSERT INTO public.sla_audit_ledger_v2
    (organization_id, type, operator_id, set_id, contract_id, plan_version, payload, occurred_at_utc)
  VALUES (
    p_organization_id, v_ledger_type, v_user::text, v_queue.set_id,
    v_queue.contract_id::uuid, 0,
    jsonb_build_object(
      'queue_entry_id', p_queue_entry_id,
      'first_reviewer_id', v_queue.first_reviewer_id,
      'second_reviewer_id', v_user,
      'confirmed_by_user_id', v_user,
      'actor_email', p_actor_email,
      'proposed_action', v_queue.peer_review_proposed_action,
      'rejection_reason', v_queue.peer_review_reason,
      'verdict_evidence', v_queue.verdict_evidence
    ),
    p_occurred_at_utc
  )
  RETURNING id INTO v_ledger_id;

  -- ── Flip terminal + wipe peer-review working state ──────────────────────────
  UPDATE public.sanction_review_queue
     SET status = v_final_status,
         reviewed_at = p_occurred_at_utc,
         reviewed_by = v_user,
         rejection_reason = CASE
           WHEN v_final_status = 'rejected' THEN v_queue.peer_review_reason
           ELSE rejection_reason
         END,
         first_reviewer_id = NULL,
         first_reviewed_at = NULL,
         peer_review_origin_status = NULL,
         peer_review_proposed_action = NULL,
         peer_review_reason = NULL,
         peer_review_expires_at = NULL
   WHERE id = p_queue_entry_id AND organization_id = p_organization_id;

  -- ── Overturn seals the snapshot in the SAME transaction (INV-21) ────────────
  IF v_ledger_type = 'DISPUTE_OVERTURNED' THEN
    v_snapshot := public.seal_dispute_resolution_snapshot(
      p_organization_id, v_ledger_id, v_queue.contract_id::uuid, v_queue.set_id,
      0, p_occurred_at_utc, v_user, p_idempotency_key);
  END IF;

  RETURN jsonb_build_object(
    'ledger_entry_id', v_ledger_id, 'status', v_final_status, 'snapshot', v_snapshot);
END;
$$;

-- ── decline_peer_review — withdraw / refuse a pending peer review ─────────────
-- Permitted to ANY auditor, including the first reviewer withdrawing their own
-- request (a withdrawal is not fraud). Reverts to the origin status.
CREATE OR REPLACE FUNCTION public.decline_peer_review(
  p_organization_id     UUID,
  p_queue_entry_id      UUID,
  p_reviewed_by_user_id UUID,
  p_actor_email         TEXT,
  p_reason              TEXT,
  p_occurred_at_utc     TIMESTAMPTZ
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_jwt_org   TEXT;
  v_jwt_role  TEXT;
  v_user      UUID;
  v_queue     public.sanction_review_queue;
  v_ledger_id UUID;
  v_origin    TEXT;
BEGIN
  v_jwt_org := auth.jwt() -> 'app_metadata' ->> 'org_id';
  IF v_jwt_org IS NULL OR v_jwt_org::uuid <> p_organization_id THEN
    RAISE EXCEPTION 'Peer review decline rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  v_jwt_role := auth.jwt() -> 'app_metadata' ->> 'role';
  IF v_jwt_role IS NULL OR v_jwt_role NOT IN ('TENANT_ADMIN', 'AUDITOR') THEN
    RAISE EXCEPTION 'Peer review decline rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  v_user := (auth.jwt() ->> 'sub')::uuid;
  IF v_user IS NULL OR v_user <> p_reviewed_by_user_id THEN
    RAISE EXCEPTION 'Peer review decline rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_queue
    FROM public.sanction_review_queue
   WHERE id = p_queue_entry_id AND organization_id = p_organization_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Peer review decline rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_queue.status <> 'pending_peer_review' THEN
    RAISE EXCEPTION 'This item is no longer awaiting a second auditor.'
      USING ERRCODE = 'P0001', DETAIL = 'IdempotencyProcessingException';
  END IF;

  v_origin := COALESCE(v_queue.peer_review_origin_status, 'pending');

  INSERT INTO public.sla_audit_ledger_v2
    (organization_id, type, operator_id, set_id, contract_id, plan_version, payload, occurred_at_utc)
  VALUES (
    p_organization_id, 'PEER_REVIEW_DECLINED', v_user::text, v_queue.set_id,
    v_queue.contract_id::uuid, 0,
    jsonb_build_object(
      'queue_entry_id', p_queue_entry_id,
      'declined_by_user_id', v_user,
      'first_reviewer_id', v_queue.first_reviewer_id,
      'actor_email', p_actor_email,
      'origin_status', v_origin,
      'proposed_action', v_queue.peer_review_proposed_action,
      'decline_reason', NULLIF(btrim(p_reason), '')
    ),
    p_occurred_at_utc
  )
  RETURNING id INTO v_ledger_id;

  UPDATE public.sanction_review_queue
     SET status = v_origin,
         first_reviewer_id = NULL,
         first_reviewed_at = NULL,
         peer_review_origin_status = NULL,
         peer_review_proposed_action = NULL,
         peer_review_reason = NULL,
         peer_review_expires_at = NULL
   WHERE id = p_queue_entry_id AND organization_id = p_organization_id;

  RETURN jsonb_build_object('ledger_entry_id', v_ledger_id, 'status', v_origin);
END;
$$;

-- ── expire_stale_peer_reviews — anti-starvation sweep (SYSTEM actor) ──────────
-- No JWT: runs as a scheduled job (pg_cron / edge). Reverts every overdue
-- pending_peer_review item to its origin and appends PEER_REVIEW_EXPIRED.
CREATE OR REPLACE FUNCTION public.expire_stale_peer_reviews()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_row   public.sanction_review_queue;
  v_now   TIMESTAMPTZ := now();
  v_count INT := 0;
BEGIN
  FOR v_row IN
    SELECT * FROM public.sanction_review_queue
     WHERE status = 'pending_peer_review'
       AND peer_review_expires_at IS NOT NULL
       AND peer_review_expires_at < v_now
     FOR UPDATE SKIP LOCKED
  LOOP
    INSERT INTO public.sla_audit_ledger_v2
      (organization_id, type, operator_id, set_id, contract_id, plan_version, payload, occurred_at_utc)
    VALUES (
      v_row.organization_id, 'PEER_REVIEW_EXPIRED', 'SYSTEM', v_row.set_id,
      v_row.contract_id::uuid, 0,
      jsonb_build_object(
        'queue_entry_id', v_row.id,
        'first_reviewer_id', v_row.first_reviewer_id,
        'origin_status', COALESCE(v_row.peer_review_origin_status, 'pending'),
        'proposed_action', v_row.peer_review_proposed_action,
        'expired_at', v_now
      ),
      v_now
    );

    UPDATE public.sanction_review_queue
       SET status = COALESCE(v_row.peer_review_origin_status, 'pending'),
           first_reviewer_id = NULL,
           first_reviewed_at = NULL,
           peer_review_origin_status = NULL,
           peer_review_proposed_action = NULL,
           peer_review_reason = NULL,
           peer_review_expires_at = NULL
     WHERE id = v_row.id AND organization_id = v_row.organization_id;

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

-- ── Grants (Max hardening) ────────────────────────────────────────────────────
-- Verdict + peer RPCs: authenticated only. Helpers: revoked from every API role
-- (called internally by the SECURITY DEFINER verdict fns, never from the client).
-- expire_stale_peer_reviews: service_role only (scheduled job), never authenticated.
REVOKE ALL ON FUNCTION public.approve_sanction(UUID, UUID, UUID, TEXT, TIMESTAMPTZ)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.approve_sanction(UUID, UUID, UUID, TEXT, TIMESTAMPTZ)
  TO authenticated;

REVOKE ALL ON FUNCTION public.reject_sanction(UUID, UUID, UUID, TEXT, TEXT, TIMESTAMPTZ)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.reject_sanction(UUID, UUID, UUID, TEXT, TEXT, TIMESTAMPTZ)
  TO authenticated;

REVOKE ALL ON FUNCTION public.resolve_dispute(UUID, UUID, TEXT, TEXT, UUID, TEXT, TIMESTAMPTZ, TEXT)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.resolve_dispute(UUID, UUID, TEXT, TEXT, UUID, TEXT, TIMESTAMPTZ, TEXT)
  TO authenticated;

REVOKE ALL ON FUNCTION public.confirm_peer_review(UUID, UUID, UUID, TEXT, TIMESTAMPTZ, TEXT)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.confirm_peer_review(UUID, UUID, UUID, TEXT, TIMESTAMPTZ, TEXT)
  TO authenticated;

REVOKE ALL ON FUNCTION public.decline_peer_review(UUID, UUID, UUID, TEXT, TEXT, TIMESTAMPTZ)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.decline_peer_review(UUID, UUID, UUID, TEXT, TEXT, TIMESTAMPTZ)
  TO authenticated;

REVOKE ALL ON FUNCTION public._resolve_dual_control_threshold(UUID, TEXT)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public._resolve_dual_control_ttl(UUID)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public._append_peer_review_requested(
  UUID, public.sanction_review_queue, UUID, TEXT, TEXT, TEXT, BIGINT, BIGINT, TIMESTAMPTZ)
  FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.expire_stale_peer_reviews()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.expire_stale_peer_reviews()
  TO service_role;
