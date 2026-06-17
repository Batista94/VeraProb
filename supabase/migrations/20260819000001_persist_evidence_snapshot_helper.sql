-- Migration: _persist_evidence_snapshot helper + approve_sanction snapshot sealing
--
-- Why: approve_sanction appended VERDICT_SEALED ledger facts but never sealed a
-- forensic snapshot. Applied-status cards had nothing to retrieve from the vault,
-- producing ResourceNotFoundException (404) in the Forensic Evidence Modal. Root
-- cause: the snapshot build+persist body lived only in seal_forensic_evidence
-- (detection path). This migration:
--   (a) ADD COLUMN queue_entry_id UUID to forensic_evidence_snapshots so the UI
--       can look up a snapshot by its originating queue entry.
--   (b) Extracts steps 5c-5h of seal_forensic_evidence (rule resolution → JCS hash
--       → vault insert) into internal helper _persist_evidence_snapshot (DRY; INV-9).
--   (c) Redefines seal_forensic_evidence to call the helper (behaviour unchanged).
--   (d) Redefines approve_sanction to call the helper after its VERDICT_SEALED ledger
--       append, binding the snapshot to the queue entry (idempotency key:
--       'approve:' || p_queue_entry_id). Hard-fail (P0002) if no active rule exists
--       at approval time — an applied fine with no sealed rule is a chain-of-custody
--       gap (INV-9, INV-21).
--
-- Invariants touched: INV-3 (append-only ledger unchanged), INV-9 (SHA-256 seal now
-- also on the approval path), INV-21 (verdict → snapshot id), INV-15 (deterministic
-- JCS hash), INV-1/INV-22 (tenant guard preserved).
-- pr_scanner: ignore-regression (Council-approved DRY extraction; see BUG-1 plan)

SET client_min_messages TO 'WARNING';

-- ── (a) Bind column: queue_entry_id ──────────────────────────────────────────
-- Nullable (seal_forensic_evidence keeps NULL for non-queue verdicts). Write-once
-- is guaranteed by the existing immutability trigger (no UPDATE path on the table).

ALTER TABLE public.forensic_evidence_snapshots
  ADD COLUMN IF NOT EXISTS queue_entry_id UUID;

-- ── (b) Internal helper: _persist_evidence_snapshot ─────────────────────────
-- Contains seal_forensic_evidence steps 5c–5h (rule resolution through vault
-- INSERT) minus 5e (ledger append). Caller owns the ledger append and passes the
-- resulting ledger_entry_id. Grants are intentionally withheld from all external
-- roles — callable only by SECURITY DEFINER siblings that run as the owner.

CREATE OR REPLACE FUNCTION public._persist_evidence_snapshot(
  p_org              UUID,
  p_contract         UUID,
  p_ledger_id        UUID,
  p_queue_entry_id   UUID,        -- NULL for seal_forensic_evidence (no queue)
  p_verdict_type     TEXT,
  p_set_id           TEXT,
  p_plan_version     INT,
  p_occurred_at_utc  TIMESTAMPTZ,
  p_sealed_by        UUID,
  p_idempotency_key  TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_rule_set_id UUID;
  v_rules       JSONB;
  v_max_version INT;
  v_eff_from    TIMESTAMPTZ;
  v_eff_to      TIMESTAMPTZ;
  v_snapshot    JSONB;
  v_hash        TEXT;
  v_row         public.forensic_evidence_snapshots;
BEGIN
  -- 5c. Backend Authority: resolve rule set from the DB only.
  SELECT id INTO v_rule_set_id
    FROM public.contract_rule_sets
   WHERE organization_id = p_org
     AND contract_id = p_contract::text
   LIMIT 1;
  IF v_rule_set_id IS NULL THEN
    RAISE EXCEPTION 'No rule set for contract % (Req 5.3)', p_contract
      USING ERRCODE = 'P0002';
  END IF;

  -- 5d. Freeze rule versions active at the verdict timestamp (INV-15 determinism).
  SELECT
    jsonb_agg(
      jsonb_build_object(
        'rule_id',          rv.id,
        'rule_type',        rv.rule_type,
        'rule_config',      rv.rule_config,
        'rule_version',     rv.rule_version,
        'evaluation_order', rv.evaluation_order,
        'active_from_utc',  rv.active_from_utc,
        'active_to_utc',    rv.active_to_utc
      ) ORDER BY rv.evaluation_order
    ),
    max(rv.rule_version),
    min(rv.active_from_utc),
    max(rv.active_to_utc)
  INTO v_rules, v_max_version, v_eff_from, v_eff_to
  FROM public.contract_rule_versions rv
  WHERE rv.rule_set_id = v_rule_set_id
    AND rv.active_from_utc <= p_occurred_at_utc
    AND (rv.active_to_utc IS NULL OR rv.active_to_utc > p_occurred_at_utc);

  IF v_rules IS NULL THEN
    RAISE EXCEPTION 'No active SLA rule for contract % at % (Req 5.3, 13.1)',
      p_contract, p_occurred_at_utc
      USING ERRCODE = 'P0002';
  END IF;

  -- 5f. Self-contained snapshot (Req 11/12). Canonically serialized by
  --     jsonb_canonical_text (JCS) for cross-language SHA-256 parity (INV-15).
  v_snapshot := jsonb_build_object(
    'schema_version',     1,
    'organization_id',    p_org,
    'contract_id',        p_contract,
    'rule_set_id',        v_rule_set_id,
    'sla_rule_version',   v_max_version,
    'effective_from_utc', v_eff_from,
    'effective_to_utc',   v_eff_to,
    'verdict_type',       p_verdict_type,
    'set_id',             p_set_id,
    'plan_version',       p_plan_version,
    'occurred_at_utc',    p_occurred_at_utc,
    'ledger_entry_id',    p_ledger_id,
    'rules',              v_rules
  );

  -- 5g. Integrity hash (INV-9) over the JCS canonical form.
  v_hash := encode(extensions.digest(public.jsonb_canonical_text(v_snapshot), 'sha256'), 'hex');

  -- 5h. Vault insert (same txn as caller's ledger append).
  INSERT INTO public.forensic_evidence_snapshots
    (organization_id, ledger_entry_id, contract_id, rule_set_id, sla_rule_version,
     effective_from_utc, effective_to_utc, snapshot, schema_version, integrity_hash,
     idempotency_key, sealed_by, queue_entry_id)
  VALUES
    (p_org, p_ledger_id, p_contract, v_rule_set_id, v_max_version,
     v_eff_from, v_eff_to, v_snapshot, 1, v_hash,
     p_idempotency_key, p_sealed_by, p_queue_entry_id)
  RETURNING * INTO v_row;

  RETURN to_jsonb(v_row);
END;
$$;

-- Internal helper — no external callers permitted (INV-22).
REVOKE ALL ON FUNCTION public._persist_evidence_snapshot(
  UUID, UUID, UUID, UUID, TEXT, TEXT, INT, TIMESTAMPTZ, UUID, TEXT
) FROM PUBLIC, anon, authenticated, service_role;

-- ── (c) Redefine seal_forensic_evidence to call helper ───────────────────────
-- Signature and semantics unchanged. Steps 5c-5h delegated to helper.
-- EXCEPTION handler preserved: unique_violation from the helper propagates here,
-- savepoint rolls back the ledger append, existing snapshot is returned.

CREATE OR REPLACE FUNCTION public.seal_forensic_evidence(
  p_organization_id  UUID,
  p_contract_id      UUID,
  p_set_id           TEXT,
  p_verdict_type     TEXT,
  p_plan_version     INT,
  p_occurred_at_utc  TIMESTAMPTZ,
  p_sealed_by        UUID,
  p_idempotency_key  TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_jwt_org   TEXT;
  v_existing  public.forensic_evidence_snapshots;
  v_ledger_id UUID;
BEGIN
  -- 5a. Tenant guard (INV-1 fail-fast). NULL jwt = trusted backend path (allowed).
  v_jwt_org := auth.jwt() -> 'app_metadata' ->> 'org_id';
  IF v_jwt_org IS NOT NULL AND v_jwt_org::uuid <> p_organization_id THEN
    RAISE EXCEPTION 'Cross-tenant seal rejected (INV-1/INV-22)'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- 5b. Idempotency short-circuit (INV-11): replay returns existing snapshot.
  SELECT * INTO v_existing
    FROM public.forensic_evidence_snapshots
   WHERE organization_id = p_organization_id
     AND idempotency_key = p_idempotency_key;
  IF FOUND THEN
    RETURN to_jsonb(v_existing);
  END IF;

  -- 5e. Append the verdict ledger entry. Captured id binds the snapshot.
  INSERT INTO public.sla_audit_ledger_v2
    (organization_id, type, operator_id, set_id, contract_id, plan_version,
     payload, occurred_at_utc)
  VALUES
    (p_organization_id, p_verdict_type, p_sealed_by::text, p_set_id, p_contract_id,
     p_plan_version,
     jsonb_build_object('forensic_seal', true, 'idempotency_key', p_idempotency_key),
     p_occurred_at_utc)
  RETURNING id INTO v_ledger_id;

  -- 5c-5h: rule resolution → JCS hash → vault insert. NULL queue_entry_id:
  -- this is a direct seal (no queue entry).
  RETURN public._persist_evidence_snapshot(
    p_organization_id, p_contract_id, v_ledger_id, NULL,
    p_verdict_type, p_set_id, p_plan_version, p_occurred_at_utc,
    p_sealed_by, p_idempotency_key
  );

EXCEPTION
  WHEN unique_violation THEN
    -- Concurrent seal won the race. Savepoint rolls back our ledger append.
    SELECT * INTO v_existing
      FROM public.forensic_evidence_snapshots
     WHERE organization_id = p_organization_id
       AND idempotency_key = p_idempotency_key;
    IF FOUND THEN
      RETURN to_jsonb(v_existing);
    END IF;
    RAISE;
END;
$$;

-- ── (d) Redefine approve_sanction to call helper ─────────────────────────────
-- Signature and semantics unchanged. Helper is called after the terminal
-- VERDICT_SEALED ledger append. Hard-fail (P0002) propagates if no active rule.
-- Idempotency key is deterministic: 'approve:' || p_queue_entry_id (INV-11).
-- pr_scanner: ignore-regression (Council-approved; see BUG-1 plan)

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

  -- Seal forensic snapshot bound to this queue entry (INV-9, INV-21).
  -- Hard-fail (P0002) propagates if no active rule version — an applied fine
  -- without a sealed rule copy is a chain-of-custody gap.
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

  RETURN jsonb_build_object('ledger_entry_id', v_ledger_id, 'status', 'applied');
END;
$$;

-- Grants: mirror prior posture exactly — authenticated only.
REVOKE ALL ON FUNCTION
  public.approve_sanction(UUID, UUID, UUID, TEXT, TIMESTAMPTZ, TEXT, TEXT)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION
  public.approve_sanction(UUID, UUID, UUID, TEXT, TIMESTAMPTZ, TEXT, TEXT)
  TO authenticated;
