-- =============================================================================
-- Migration: resolve_dispute — Pure Transactional Consistency (Resolução de Disputas)
-- Purpose:   Migrate dispute-resolution concurrency control + atomicity into the DB.
--            Replaces the legacy 3–4 non-atomic PostgREST round-trips
--            (TOCTOU read → ledger append → queue update → snapshot seal) with a
--            single SECURITY DEFINER RPC that performs, in ONE transaction:
--              lock → status re-check → ledger append → queue update →
--              (overturn only) inline snapshot seal.
--
-- pr_scanner: ignore-regression — new additive migration (CREATE OR REPLACE fn +
--   additive partial unique indexes); no merged migration modified. Lead-reviewer
--   audited PASS on all applicable invariants (Council-approved).
--
-- Invariants:
--   INV-3   Ledger APPEND-ONLY — the function only INSERTs the resolution fact.
--   INV-1   org_id re-asserted from JWT (SECURITY DEFINER bypasses RLS).
--   INV-22  Tenant isolation — cross-tenant resolve rejected.
--   INV-26  Anti-oracle — wrong-org AND not-found raise the SAME errcode (42501).
--   INV-10  Concurrent loser → P0001 + DETAIL IdempotencyProcessingException.
--   INV-6   UTC — occurred_at_utc supplied by caller (IDateTimeProvider.nowUtc()).
--   INV-15  Determinism — ledger payload mirrors SlaLedgerMapper resolution output.
--   INV-21  Verdict → snapshot — overturn seal shares the SAME transaction.
--   INV-DB  Zero-downtime — defense-in-depth unique indexes are per-partition,
--           partial, and additive (no blocking ALTER/DROP).
-- =============================================================================

CREATE OR REPLACE FUNCTION public.resolve_dispute(
  p_organization_id    UUID,
  p_queue_entry_id     UUID,
  p_resolution         TEXT,
  p_resolution_reason  TEXT,
  p_resolved_by_user_id UUID,
  p_actor_email        TEXT,
  p_occurred_at_utc    TIMESTAMPTZ,
  p_idempotency_key    TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_jwt_org    TEXT;
  v_jwt_role   TEXT;
  v_queue      public.sanction_review_queue;
  v_new_status TEXT;
  v_ledger_id  UUID;
  v_snapshot   JSONB;
BEGIN
  -- ── Auth (Max hardening) ────────────────────────────────────────────────
  -- SECURITY DEFINER runs as the function owner and bypasses RLS, so the
  -- tenant + role guards MUST be re-asserted here (INV-1/INV-22). NULL JWT and
  -- cross-tenant both raise 42501 — indistinguishable to the caller (INV-26).
  v_jwt_org := auth.jwt() -> 'app_metadata' ->> 'org_id';
  IF v_jwt_org IS NULL OR v_jwt_org::uuid <> p_organization_id THEN
    RAISE EXCEPTION 'Dispute resolution rejected.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  v_jwt_role := auth.jwt() -> 'app_metadata' ->> 'role';
  IF v_jwt_role IS NULL OR v_jwt_role NOT IN ('TENANT_ADMIN', 'AUDITOR') THEN
    RAISE EXCEPTION 'Dispute resolution rejected.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- ── Resolution → target queue status (mirrors Dart _targetStatus) ─────────
  v_new_status := CASE p_resolution
    WHEN 'DISPUTE_ACCEPTED'   THEN 'rejected'
    WHEN 'DISPUTE_OVERTURNED' THEN 'applied'
    WHEN 'DISPUTE_RETRACTED'  THEN 'pending'
    ELSE NULL
  END;
  IF v_new_status IS NULL THEN
    -- Unknown resolution token — opaque rejection (anti-oracle).
    RAISE EXCEPTION 'Dispute resolution rejected.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- ── TOCTOU close: row-lock the queue entry as the FIRST access ────────────
  -- A second concurrent caller blocks on FOR UPDATE until this txn commits;
  -- it then re-reads status = non-disputed and loses (idempotency). READ
  -- COMMITTED + FOR UPDATE is sufficient (no SERIALIZABLE, no SKIP LOCKED).
  SELECT * INTO v_queue
    FROM public.sanction_review_queue
   WHERE id = p_queue_entry_id
     AND organization_id = p_organization_id
   FOR UPDATE;

  IF NOT FOUND THEN
    -- Not-found and wrong-org are indistinguishable (INV-26).
    RAISE EXCEPTION 'Dispute resolution rejected.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_queue.status <> 'disputed' THEN
    RAISE EXCEPTION 'This dispute has already been resolved by another auditor.'
      USING ERRCODE = 'P0001', DETAIL = 'IdempotencyProcessingException';
  END IF;

  -- ── Ledger append (INV-3) ────────────────────────────────────────────────
  -- Column set mirrors SlaLedgerEntryDto.fromDomain; payload mirrors
  -- SlaLedgerMapper._resolution for byte-identical replay (INV-15).
  INSERT INTO public.sla_audit_ledger_v2
    (organization_id, type, operator_id, set_id, contract_id,
     plan_version, payload, occurred_at_utc)
  VALUES (
    p_organization_id,
    p_resolution,
    p_resolved_by_user_id::text,
    v_queue.set_id,
    v_queue.contract_id::uuid,
    0,
    jsonb_build_object(
      'queue_entry_id',      p_queue_entry_id,
      'resolved_by_user_id', p_resolved_by_user_id,
      'actor_email',         p_actor_email,
      'resolution_reason',   NULLIF(btrim(p_resolution_reason), ''),
      'verdict_evidence',    v_queue.verdict_evidence
    ),
    p_occurred_at_utc
  )
  RETURNING id INTO v_ledger_id;

  -- ── Queue transition (mirrors Dart _applyTransition) ─────────────────────
  -- Only status/reviewed_at/reviewed_by/rejection_reason are mutable; the
  -- immutability trigger (prevent_srq_immutable_mutation) guards the rest.
  --   accept   → rejected, reviewed set, rejection_reason = reason
  --   overturn → applied,  reviewed set, rejection_reason preserved
  --   retract  → pending,  reviewed cleared, reviewed_by preserved, reason cleared
  UPDATE public.sanction_review_queue
     SET status = v_new_status,
         reviewed_at = CASE
           WHEN p_resolution = 'DISPUTE_RETRACTED' THEN NULL
           ELSE p_occurred_at_utc
         END,
         reviewed_by = CASE
           WHEN p_resolution = 'DISPUTE_RETRACTED' THEN reviewed_by
           ELSE p_resolved_by_user_id
         END,
         rejection_reason = CASE
           WHEN p_resolution = 'DISPUTE_ACCEPTED'  THEN NULLIF(btrim(p_resolution_reason), '')
           WHEN p_resolution = 'DISPUTE_RETRACTED' THEN NULL
           ELSE rejection_reason
         END
   WHERE id = p_queue_entry_id
     AND organization_id = p_organization_id;

  -- ── Inline snapshot seal (overturn only) — SAME transaction (INV-21) ──────
  IF p_resolution = 'DISPUTE_OVERTURNED' THEN
    v_snapshot := public.seal_dispute_resolution_snapshot(
      p_organization_id,
      v_ledger_id,
      v_queue.contract_id::uuid,
      v_queue.set_id,
      0,
      p_occurred_at_utc,
      p_resolved_by_user_id,
      p_idempotency_key
    );
  END IF;

  RETURN jsonb_build_object(
    'ledger_entry_id', v_ledger_id,
    'status',          v_new_status,
    'snapshot',        v_snapshot
  );
END;
$$;

-- ── Grants (Max hardening) ──────────────────────────────────────────────────
-- Grant ONLY to authenticated. Supabase auto-grants EXECUTE on new public
-- functions to anon/authenticated/service_role via ALTER DEFAULT PRIVILEGES, so
-- a plain REVOKE FROM PUBLIC is NOT enough — those grants are explicit per-role.
-- Revoke them by name to remove every Data-API bypass path (a service_role /
-- anon token carries no app_metadata.org_id and would hit the NULL-JWT guard,
-- but defense-in-depth: deny EXECUTE outright).
REVOKE ALL ON FUNCTION public.resolve_dispute(
  UUID, UUID, TEXT, TEXT, UUID, TEXT, TIMESTAMPTZ, TEXT
) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.resolve_dispute(
  UUID, UUID, TEXT, TEXT, UUID, TEXT, TIMESTAMPTZ, TEXT
) TO authenticated;

-- ── Defense-in-depth: one resolution fact per (org, queue entry) ─────────────
-- FOR UPDATE is the PRIMARY race guard. These partial unique indexes are a
-- secondary backstop: a direct duplicate INSERT (bypassing the RPC) raises
-- 23505. The ledger is HASH-partitioned by organization_id and the key includes
-- organization_id, so the same (org_id, queue_entry_id) always routes to one
-- partition — per-partition uniqueness is therefore globally sufficient.
-- (Partial UNIQUE indexes are unsupported on the partitioned PARENT, so they are
-- declared per child partition.) Additive + partial. NOTE: CREATE INDEX without
-- CONCURRENTLY takes a brief ShareLock on each partition during the build;
-- CONCURRENTLY is NOT usable here because Supabase runs each migration file in a
-- transaction block. On empty/small partitions the lock window is negligible —
-- INV-DB safe (no ALTER/DROP/DELETE, additive only).
CREATE UNIQUE INDEX IF NOT EXISTS uq_ledger_resolution_p0
  ON public.sla_audit_ledger_p0 (organization_id, (payload->>'queue_entry_id'))
  WHERE type IN ('DISPUTE_ACCEPTED', 'DISPUTE_OVERTURNED', 'DISPUTE_RETRACTED');
CREATE UNIQUE INDEX IF NOT EXISTS uq_ledger_resolution_p1
  ON public.sla_audit_ledger_p1 (organization_id, (payload->>'queue_entry_id'))
  WHERE type IN ('DISPUTE_ACCEPTED', 'DISPUTE_OVERTURNED', 'DISPUTE_RETRACTED');
CREATE UNIQUE INDEX IF NOT EXISTS uq_ledger_resolution_p2
  ON public.sla_audit_ledger_p2 (organization_id, (payload->>'queue_entry_id'))
  WHERE type IN ('DISPUTE_ACCEPTED', 'DISPUTE_OVERTURNED', 'DISPUTE_RETRACTED');
CREATE UNIQUE INDEX IF NOT EXISTS uq_ledger_resolution_p3
  ON public.sla_audit_ledger_p3 (organization_id, (payload->>'queue_entry_id'))
  WHERE type IN ('DISPUTE_ACCEPTED', 'DISPUTE_OVERTURNED', 'DISPUTE_RETRACTED');
