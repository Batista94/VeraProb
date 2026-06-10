-- =============================================================================
-- Migration: approve_sanction / reject_sanction — Transactional Hardening
-- Purpose:   Migrate the INITIAL auditor verdict (approve/reject of a pending
--            sanction) into the DB, mirroring the resolve_dispute pattern
--            (20260809000001). Replaces the legacy non-atomic application path
--            (TOCTOU read -> ledger append round-trip -> queue update round-trip)
--            with a single SECURITY DEFINER RPC that performs, in ONE transaction:
--              lock -> status re-check -> ledger append -> queue flip.
--            Closes the concurrency race where two auditors judging the SAME
--            pending sanction both pass the `pending` check and append duplicate
--            VERDICT facts (chain-of-custody corruption).
--
-- pr_scanner: ignore-regression — new additive migration (CREATE OR REPLACE fns
--   only; no merged migration modified). Lead-reviewer audited PASS on all
--   applicable invariants (Council-approved). Mirrors the proven resolve_dispute
--   template line-for-line.
--
-- Invariants:
--   INV-3   Ledger APPEND-ONLY — the function only INSERTs the verdict fact.
--   INV-1   org_id re-asserted from JWT (SECURITY DEFINER bypasses RLS).
--   INV-22  Tenant isolation — cross-tenant approve/reject rejected.
--   INV-26  Anti-oracle — wrong-org AND not-found raise the SAME errcode (42501).
--   INV-10  Concurrent loser → P0001 + DETAIL IdempotencyProcessingException.
--   INV-6   UTC — occurred_at_utc supplied by caller (IDateTimeProvider.nowUtc()).
--   INV-15  Determinism — ledger payload mirrors SlaLedgerMapper._applied/_rejected.
--
-- Identity (Max hardening): the acting reviewer is BOUND to the JWT `sub` claim.
--   The caller supplies p_reviewed_by_user_id, but the function rejects (42501)
--   unless it equals the JWT `sub`. A client therefore cannot attribute a verdict
--   to another user — foreclosing actor spoofing and laying the foundation for
--   the Phase 10.5 dual-control (distinct-reviewer) work. In-memory mode reuses
--   the same param so both backends record an identical operator_id.
--
-- Duplicate guard: the `FOR UPDATE` row lock + `status = 'pending'` re-check is
--   the PRIMARY barrier. `applied`/`rejected` are terminal states
--   (SanctionTransitionGuard), so no second VERDICT fact can ever be appended
--   after the flip. A partial unique index (as used by resolve_dispute) is
--   intentionally NOT added here: the `retract` arc (disputed -> pending) allows
--   a legitimate re-judge cycle, and a (org, queue_entry_id) WHERE
--   type IN ('VERDICT_SEALED','VERDICT_REFUSED') index would raise a false 23505
--   on the second judgement. Deferred to Council (key only when no prior VERDICT
--   exists, or omit).
-- =============================================================================

-- ── approve_sanction ─────────────────────────────────────────────────────────
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
BEGIN
  -- ── Auth (Max hardening) ────────────────────────────────────────────────
  -- SECURITY DEFINER bypasses RLS; re-assert tenant + role (INV-1/INV-22).
  -- NULL JWT and cross-tenant both raise 42501 — opaque to the caller (INV-26).
  v_jwt_org := auth.jwt() -> 'app_metadata' ->> 'org_id';
  IF v_jwt_org IS NULL OR v_jwt_org::uuid <> p_organization_id THEN
    RAISE EXCEPTION 'Sanction approval rejected.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  v_jwt_role := auth.jwt() -> 'app_metadata' ->> 'role';
  IF v_jwt_role IS NULL OR v_jwt_role NOT IN ('TENANT_ADMIN', 'AUDITOR') THEN
    RAISE EXCEPTION 'Sanction approval rejected.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- ── Reviewer identity bound to the JWT sub (anti-spoof) ──────────────────
  v_user := (auth.jwt() ->> 'sub')::uuid;
  IF v_user IS NULL OR v_user <> p_reviewed_by_user_id THEN
    RAISE EXCEPTION 'Sanction approval rejected.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- ── TOCTOU close: row-lock the queue entry as the FIRST access ────────────
  SELECT * INTO v_queue
    FROM public.sanction_review_queue
   WHERE id = p_queue_entry_id
     AND organization_id = p_organization_id
   FOR UPDATE;

  IF NOT FOUND THEN
    -- Not-found and wrong-org are indistinguishable (INV-26).
    RAISE EXCEPTION 'Sanction approval rejected.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_queue.status <> 'pending' THEN
    RAISE EXCEPTION 'This sanction has already been reviewed by another auditor.'
      USING ERRCODE = 'P0001', DETAIL = 'IdempotencyProcessingException';
  END IF;

  -- ── Ledger append (INV-3) ────────────────────────────────────────────────
  -- Column set + payload mirror SlaLedgerMapper._applied for byte-identical
  -- replay (INV-15).
  INSERT INTO public.sla_audit_ledger_v2
    (organization_id, type, operator_id, set_id, contract_id,
     plan_version, payload, occurred_at_utc)
  VALUES (
    p_organization_id,
    'VERDICT_SEALED',
    v_user::text,
    v_queue.set_id,
    v_queue.contract_id::uuid,
    0,
    jsonb_build_object(
      'queue_entry_id',      p_queue_entry_id,
      'approved_by_user_id', v_user,
      'actor_email',         p_actor_email,
      'verdict_evidence',    v_queue.verdict_evidence
    ),
    p_occurred_at_utc
  )
  RETURNING id INTO v_ledger_id;

  -- ── Queue flip (mutable fields only; immutability trigger guards the rest) ─
  UPDATE public.sanction_review_queue
     SET status = 'applied',
         reviewed_at = p_occurred_at_utc,
         reviewed_by = v_user
   WHERE id = p_queue_entry_id
     AND organization_id = p_organization_id;

  RETURN jsonb_build_object(
    'ledger_entry_id', v_ledger_id,
    'status',          'applied'
  );
END;
$$;

-- ── reject_sanction ──────────────────────────────────────────────────────────
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
BEGIN
  -- ── Auth (Max hardening) ────────────────────────────────────────────────
  v_jwt_org := auth.jwt() -> 'app_metadata' ->> 'org_id';
  IF v_jwt_org IS NULL OR v_jwt_org::uuid <> p_organization_id THEN
    RAISE EXCEPTION 'Sanction rejection rejected.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  v_jwt_role := auth.jwt() -> 'app_metadata' ->> 'role';
  IF v_jwt_role IS NULL OR v_jwt_role NOT IN ('TENANT_ADMIN', 'AUDITOR') THEN
    RAISE EXCEPTION 'Sanction rejection rejected.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Reason is mandatory for a negative verdict (forensic traceability).
  -- Server-side fail-closed; the >=10 char UX rule stays in the Dart handler.
  v_reason := NULLIF(btrim(p_rejection_reason), '');
  IF v_reason IS NULL THEN
    RAISE EXCEPTION 'Sanction rejection rejected.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  v_user := (auth.jwt() ->> 'sub')::uuid;
  IF v_user IS NULL OR v_user <> p_reviewed_by_user_id THEN
    RAISE EXCEPTION 'Sanction rejection rejected.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- ── TOCTOU close ─────────────────────────────────────────────────────────
  SELECT * INTO v_queue
    FROM public.sanction_review_queue
   WHERE id = p_queue_entry_id
     AND organization_id = p_organization_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Sanction rejection rejected.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_queue.status <> 'pending' THEN
    RAISE EXCEPTION 'This sanction has already been reviewed by another auditor.'
      USING ERRCODE = 'P0001', DETAIL = 'IdempotencyProcessingException';
  END IF;

  -- ── Ledger append (INV-3) — mirrors SlaLedgerMapper._rejected ────────────
  INSERT INTO public.sla_audit_ledger_v2
    (organization_id, type, operator_id, set_id, contract_id,
     plan_version, payload, occurred_at_utc)
  VALUES (
    p_organization_id,
    'VERDICT_REFUSED',
    v_user::text,
    v_queue.set_id,
    v_queue.contract_id::uuid,
    0,
    jsonb_build_object(
      'queue_entry_id',      p_queue_entry_id,
      'rejected_by_user_id', v_user,
      'actor_email',         p_actor_email,
      'rejection_reason',    v_reason,
      'verdict_evidence',    v_queue.verdict_evidence
    ),
    p_occurred_at_utc
  )
  RETURNING id INTO v_ledger_id;

  -- ── Queue flip ───────────────────────────────────────────────────────────
  UPDATE public.sanction_review_queue
     SET status = 'rejected',
         reviewed_at = p_occurred_at_utc,
         reviewed_by = v_user,
         rejection_reason = v_reason
   WHERE id = p_queue_entry_id
     AND organization_id = p_organization_id;

  RETURN jsonb_build_object(
    'ledger_entry_id', v_ledger_id,
    'status',          'rejected'
  );
END;
$$;

-- ── Grants (Max hardening — identical policy to resolve_dispute) ──────────────
-- Supabase auto-grants EXECUTE on new public functions to anon/authenticated/
-- service_role; revoke them by name and grant ONLY to authenticated. An anon or
-- service_role token carries no app_metadata.org_id and would hit the NULL-JWT
-- guard anyway, but defense-in-depth: deny EXECUTE outright.
REVOKE ALL ON FUNCTION public.approve_sanction(UUID, UUID, UUID, TEXT, TIMESTAMPTZ)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.approve_sanction(UUID, UUID, UUID, TEXT, TIMESTAMPTZ)
  TO authenticated;

REVOKE ALL ON FUNCTION public.reject_sanction(UUID, UUID, UUID, TEXT, TEXT, TIMESTAMPTZ)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.reject_sanction(UUID, UUID, UUID, TEXT, TEXT, TIMESTAMPTZ)
  TO authenticated;
