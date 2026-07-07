-- pr_scanner: ignore-regression
-- =============================================================================
-- Migration: 20260910000001 — Live-check O(1) for sensitive mutation RPCs (Pilar 1.5)
--
-- Adds _rbac_live_check_permission(text) internal helper that verifies a custom
-- RBAC permission is still active in the DB even when the JWT claim is stale
-- (TTL not yet expired). Injects the check into approve_sanction and
-- reject_sanction immediately after the coarse-role guard.
--
-- Additive pattern:
--   • TENANT_ADMIN / SuperAdmin (has_permission('*'))  → bypass, no DB hit
--   • Coarse AUDITOR with no custom permissions        → bypass (claim absent)
--   • User with custom sla:approve + claim revoked     → 42501 immediately
--
-- Invariants: INV-1, INV-2, INV-10, INV-21, INV-22.
-- Council sign-off: QA/Security | Lead Reviewer
-- pr_scanner: ignore-regression
-- =============================================================================

SET client_min_messages TO 'WARNING';

-- ── Internal helper: O(1) live-check for a custom RBAC permission ─────────────
-- Behaviour:
--   1. has_permission('*')    → return (wildcard, no DB hit)
--   2. NOT has_permission(p)  → return (coarse-role user, permission not in JWT)
--   3. has_permission(p) + DB check: active row in user_tenant_roles → return OK
--   4. has_permission(p) + row missing/revoked → RAISE '42501'
--
-- Called only from SECURITY DEFINER RPCs; REVOKED from client roles.
CREATE OR REPLACE FUNCTION public._rbac_live_check_permission(p_perm text)
RETURNS void
LANGUAGE plpgsql
SET search_path = public, auth
AS $$
DECLARE
  v_caller_id uuid;
  v_org_id    uuid;
BEGIN
  -- Wildcard holders (TENANT_ADMIN / SuperAdmin) bypass DB lookup.
  IF public.has_permission('*') THEN
    RETURN;
  END IF;

  -- Coarse-role users without this custom permission bypass the DB check.
  IF NOT public.has_permission(p_perm) THEN
    RETURN;
  END IF;

  v_caller_id := (auth.jwt() ->> 'sub')::uuid;
  v_org_id    := (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid;

  IF v_caller_id IS NULL OR v_org_id IS NULL THEN
    RAISE EXCEPTION 'Permission revoked or insufficient'
      USING ERRCODE = '42501';
  END IF;

  -- O(1) PK-indexed lookup — not in RLS; pointual check inside SECURITY DEFINER context.
  -- Indexes: idx_user_tenant_roles_user_active, idx_tenant_role_permissions_role
  IF NOT EXISTS (
    SELECT 1
      FROM public.user_tenant_roles utr
      JOIN public.tenant_role_permissions trp
        ON trp.tenant_role_id = utr.tenant_role_id
       AND trp.permission_key = p_perm
     WHERE utr.user_id         = v_caller_id
       AND utr.organization_id = v_org_id
       AND utr.revoked_at IS NULL
       AND utr.valid_from <= NOW()
       AND (utr.valid_until IS NULL OR utr.valid_until > NOW())
  ) THEN
    RAISE EXCEPTION 'Permission revoked or insufficient'
      USING ERRCODE = '42501';
  END IF;
END;
$$;

-- Internal-only: not callable by API clients.
REVOKE ALL ON FUNCTION public._rbac_live_check_permission(text) FROM PUBLIC, anon, authenticated;

-- ── reject_sanction — verbatim from 20260903000003 + live-check injected ──────
CREATE OR REPLACE FUNCTION public.reject_sanction(
  p_organization_id     UUID,
  p_queue_entry_id      UUID,
  p_reviewed_by_user_id UUID,
  p_actor_email         TEXT,
  p_rejection_reason    TEXT,
  p_reason_code         TEXT,
  p_occurred_at_utc     TIMESTAMPTZ
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  v_jwt_org TEXT; v_jwt_role TEXT; v_user UUID; v_reason TEXT;
  v_queue public.sanction_review_queue; v_ledger_id UUID;
  v_fine BIGINT; v_threshold BIGINT; v_ttl INT;
BEGIN
  v_jwt_org := auth.jwt() -> 'app_metadata' ->> 'org_id';
  IF v_jwt_org IS NULL OR v_jwt_org::uuid <> p_organization_id THEN
    RAISE EXCEPTION 'Sanction rejection rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  v_jwt_role := auth.jwt() -> 'app_metadata' ->> 'role';
  IF v_jwt_role IS NULL OR v_jwt_role NOT IN ('TENANT_ADMIN', 'AUDITOR') THEN
    RAISE EXCEPTION 'Sanction rejection rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Additive live-check: stale custom sla:approve claim verified against DB (INV-1.5).
  -- Coarse AUDITOR / TENANT_ADMIN without custom permissions bypass transparently.
  PERFORM public._rbac_live_check_permission('sla:approve');

  v_reason := NULLIF(btrim(p_rejection_reason), '');
  IF p_reason_code IS NULL OR btrim(p_reason_code) = '' THEN
    RAISE EXCEPTION 'Sanction rejection rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.dispute_reason_codes
                  WHERE code = p_reason_code AND is_active = TRUE AND organization_id IS NULL) THEN
    RAISE EXCEPTION 'Sanction rejection rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  v_user := (auth.jwt() ->> 'sub')::uuid;
  IF v_user IS NULL OR v_user <> p_reviewed_by_user_id THEN
    RAISE EXCEPTION 'Sanction rejection rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- ── TOCTOU close with NOWAIT ───────────────────────────────────────────────
  SELECT * INTO v_queue FROM public.sanction_review_queue
   WHERE id = p_queue_entry_id AND organization_id = p_organization_id FOR UPDATE NOWAIT;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Sanction rejection rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF v_queue.status <> 'pending' THEN
    RAISE EXCEPTION 'This sanction has already been reviewed by another auditor.'
      USING ERRCODE = 'P0001', DETAIL = 'IdempotencyProcessingException';
  END IF;

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
           peer_review_reason_code = p_reason_code,
           peer_review_expires_at = p_occurred_at_utc + make_interval(hours => v_ttl)
     WHERE id = p_queue_entry_id AND organization_id = p_organization_id;
    v_ledger_id := public._append_peer_review_requested(
      p_organization_id, v_queue, v_user, p_actor_email, 'REJECT',
      v_reason, v_fine, v_threshold, p_occurred_at_utc);
    RETURN jsonb_build_object('ledger_entry_id', v_ledger_id, 'status', 'pending_peer_review');
  END IF;

  INSERT INTO public.sla_audit_ledger_v2
    (organization_id, type, operator_id, set_id, contract_id, plan_version, payload, occurred_at_utc)
  VALUES (
    p_organization_id, 'VERDICT_REFUSED', v_user::text, v_queue.set_id,
    v_queue.contract_id::uuid, 0,
    jsonb_build_object(
      'queue_entry_id', p_queue_entry_id, 'rejected_by_user_id', v_user,
      'actor_email', p_actor_email, 'rejection_reason', v_reason,
      'reason_code', p_reason_code, 'verdict_evidence', v_queue.verdict_evidence),
    p_occurred_at_utc)
  RETURNING id INTO v_ledger_id;

  UPDATE public.sanction_review_queue
     SET status = 'rejected', reviewed_at = p_occurred_at_utc, reviewed_by = v_user,
         rejection_reason = v_reason, rejection_reason_code = p_reason_code
   WHERE id = p_queue_entry_id AND organization_id = p_organization_id;

  -- Seal forensic snapshot bound to this queue entry (INV-9, INV-21).
  PERFORM public._persist_evidence_snapshot(
    p_organization_id, v_queue.contract_id::uuid, v_ledger_id, p_queue_entry_id,
    'VERDICT_REFUSED', v_queue.set_id, 0, p_occurred_at_utc, v_user,
    'reject:' || p_queue_entry_id::text
  );

  UPDATE public.dispute_portal_tokens
     SET revoked_at_utc = p_occurred_at_utc, revoked_reason = 'VERDICT_SEALED'
   WHERE organization_id = p_organization_id
     AND queue_entry_id  = p_queue_entry_id
     AND revoked_at_utc IS NULL;

  RETURN jsonb_build_object('ledger_entry_id', v_ledger_id, 'status', 'rejected');
END;
$$;

-- ── approve_sanction — verbatim from 20260903000003 + live-check injected ─────
CREATE OR REPLACE FUNCTION public.approve_sanction(
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

  -- Additive live-check: stale custom sla:approve claim verified against DB (INV-1.5).
  -- Coarse AUDITOR / TENANT_ADMIN without custom permissions bypass transparently.
  PERFORM public._rbac_live_check_permission('sla:approve');

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

  -- ── TOCTOU close with NOWAIT ───────────────────────────────────────────────
  SELECT * INTO v_queue
    FROM public.sanction_review_queue
   WHERE id = p_queue_entry_id AND organization_id = p_organization_id
   FOR UPDATE NOWAIT;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Sanction approval rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_queue.status <> 'pending' THEN
    RAISE EXCEPTION 'This sanction has already been reviewed by another auditor.'
      USING ERRCODE = 'P0001', DETAIL = 'IdempotencyProcessingException';
  END IF;

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

  -- ── Terminal path: seal verdict ──────────────────────────────────────────────
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

  PERFORM public._persist_evidence_snapshot(
    p_organization_id,
    v_queue.contract_id::uuid,
    v_ledger_id,
    p_queue_entry_id,
    'VERDICT_SEALED',
    v_queue.set_id,
    0,
    p_occurred_at_utc,
    v_user,
    'approve:' || p_queue_entry_id::text
  );

  UPDATE public.sanction_review_queue
     SET status = 'applied', reviewed_at = p_occurred_at_utc, reviewed_by = v_user
   WHERE id = p_queue_entry_id AND organization_id = p_organization_id;

  UPDATE public.dispute_portal_tokens
     SET revoked_at_utc = p_occurred_at_utc, revoked_reason = 'VERDICT_SEALED'
   WHERE organization_id = p_organization_id
     AND queue_entry_id  = p_queue_entry_id
     AND revoked_at_utc IS NULL;

  RETURN jsonb_build_object('ledger_entry_id', v_ledger_id, 'status', 'applied');
END;
$$;

-- Re-affirm grants (unchanged from 20260903000003).
REVOKE ALL ON FUNCTION public.reject_sanction(UUID, UUID, UUID, TEXT, TEXT, TEXT, TIMESTAMPTZ)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.reject_sanction(UUID, UUID, UUID, TEXT, TEXT, TEXT, TIMESTAMPTZ)
  TO authenticated;

REVOKE ALL ON FUNCTION public.approve_sanction(UUID, UUID, UUID, TEXT, TIMESTAMPTZ, TEXT, TEXT)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.approve_sanction(UUID, UUID, UUID, TEXT, TIMESTAMPTZ, TEXT, TEXT)
  TO authenticated;

RESET client_min_messages;
