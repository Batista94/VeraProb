-- =============================================================================
-- Migration: attach_dispute_evidence RPC — atomic, ownership-checked metadata
-- Purpose:   The ONLY path to insert dispute_evidence_attachments. Closes B4
--            (queue ownership) and H2 (TOCTOU on the 10-attachment limit) via an
--            advisory lock keyed on (organization_id, queue_entry_id).
--
-- Invariants: INV-1, INV-9, INV-10, INV-22, INV-26.
-- NOTE: the audit fact uses ledger type 'DISPUTE_EVIDENCE_ATTACHED'. The widening
--       of chk_ledger_type for this type is folded into THIS migration (below) so
--       the RPC is self-contained and deployable in isolation — an RPC that writes
--       a ledger type the live schema rejects is a broken deploy. Migration 007
--       (H1) widens further for the SLA-breach types only.
-- =============================================================================

-- ── H1-safe widening of chk_ledger_type to admit DISPUTE_EVIDENCE_ATTACHED ───
-- Superset of the prior 20260812000002 list + the new type. Add the superset
-- under a temp name (NOT VALID → no blocking validation scan, existing rows
-- already conform), drop the old guard, then rename the temp back to the stable
-- name `chk_ledger_type`. The table is never without a type guard, and the
-- canonical constraint name is preserved (downstream tests/migrations key on it).
ALTER TABLE public.sla_audit_ledger_v2 DROP CONSTRAINT IF EXISTS chk_ledger_type_tmp;
ALTER TABLE public.sla_audit_ledger_v2
  ADD CONSTRAINT chk_ledger_type_tmp CHECK (type IN (
    'EXECUTION_BOUND',
    'NO_SHOW_DECLARED',
    'EVIDENCE_GAP_DECLARED',
    'PLAN_DECLARED',
    'OCCURRENCE_REGISTERED',
    'TRIP_INTERRUPTED',
    'TRIP_CANCELLED',
    'CONTRACT_CREATED',
    'CONTRACT_ACTIVATED',
    'CONTRACT_CLOSED',
    'CONTRACT_SUBMITTED_FOR_APPROVAL',
    'CONTRACT_ACCEPTED_BY_CONTRACTOR',
    'SANCTION_RECOMMENDED',
    'VERDICT_SEALED',
    'VERDICT_REFUSED',
    'SANCTION_DISPUTED',
    'DISPUTE_ACCEPTED',
    'DISPUTE_OVERTURNED',
    'DISPUTE_RETRACTED',
    'JUSTIFICATION_SUBMITTED',
    'JUSTIFICATION_APPROVED',
    'JUSTIFICATION_REJECTED',
    'SLA_JUSTIFICATION_SUBMITTED',
    'SLA_JUSTIFICATION_EXPIRED',
    'TRANSIT_STARTED',
    'COMPLETED_WITH_GAPS',
    'EXECUTION_INHIBITED',
    'UNKNOWN_EVENT',
    'MAX_TOLERANCE_DELAY',
    'MAX_EVIDENCE_GAP',
    'MIN_GEOFENCE_COVERAGE',
    'NO_SHOW_PENALTY',
    'PEER_REVIEW_REQUESTED',
    'PEER_REVIEW_DECLINED',
    'PEER_REVIEW_EXPIRED',
    'DUAL_CONTROL_THRESHOLD_CHANGED',
    -- Phase 10.6 (Item B4): evidence attachment fact (ADD-1)
    'DISPUTE_EVIDENCE_ATTACHED'
  )) NOT VALID; -- INV-DB: zero-downtime-verified (superset; existing rows already conform)
ALTER TABLE public.sla_audit_ledger_v2 VALIDATE CONSTRAINT chk_ledger_type_tmp;
ALTER TABLE public.sla_audit_ledger_v2 DROP CONSTRAINT IF EXISTS chk_ledger_type; -- INV-DB: zero-downtime-verified (superseded by chk_ledger_type_tmp, renamed below)
ALTER TABLE public.sla_audit_ledger_v2 RENAME CONSTRAINT chk_ledger_type_tmp TO chk_ledger_type;

CREATE OR REPLACE FUNCTION public.attach_dispute_evidence(
  p_organization_id UUID,
  p_queue_entry_id  UUID,
  p_storage_path    TEXT,
  p_file_name       TEXT,
  p_mime_type       TEXT,
  p_file_size_bytes BIGINT,
  p_sha256_hash     TEXT,
  p_uploaded_by     UUID,
  p_attached_at_utc TIMESTAMPTZ
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_jwt_org  TEXT;
  v_jwt_role TEXT;
  v_user     UUID;
  v_queue    public.sanction_review_queue;
  v_count    INT;
  v_id       UUID;
BEGIN
  -- Auth (anti-oracle: every failure → 42501, generic message; INV-26)
  v_jwt_org := auth.jwt() -> 'app_metadata' ->> 'org_id';
  IF v_jwt_org IS NULL OR v_jwt_org::uuid <> p_organization_id THEN
    RAISE EXCEPTION 'Evidence rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  v_jwt_role := auth.jwt() -> 'app_metadata' ->> 'role';
  IF v_jwt_role IS NULL OR v_jwt_role NOT IN ('TENANT_ADMIN','AUDITOR') THEN
    RAISE EXCEPTION 'Evidence rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  v_user := (auth.jwt() ->> 'sub')::uuid;
  IF v_user IS NULL OR v_user <> p_uploaded_by THEN
    RAISE EXCEPTION 'Evidence rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Path must be exactly {org_id}/{queue_entry_id}/... (B4)
  IF p_storage_path !~ ('^' || p_organization_id::text || '/' || p_queue_entry_id::text || '/') THEN
    RAISE EXCEPTION 'Evidence rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Serialize concurrent uploads for this dispute (H2: TOCTOU). Single 64-bit
  -- key over the (org, queue) pair — the two-arg lock form takes int4, not the
  -- bigint that hashtextextended returns.
  PERFORM pg_advisory_xact_lock(
    hashtextextended(p_organization_id::text || '/' || p_queue_entry_id::text, 0)
  );

  -- Ownership + state: queue must belong to org and be disputed.
  SELECT * INTO v_queue
    FROM public.sanction_review_queue
   WHERE id = p_queue_entry_id AND organization_id = p_organization_id
   FOR SHARE;
  IF NOT FOUND OR v_queue.status <> 'disputed' THEN
    RAISE EXCEPTION 'Evidence rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- ADD-3 limit, now race-free under the advisory lock.
  SELECT count(*) INTO v_count
    FROM public.dispute_evidence_attachments
   WHERE organization_id = p_organization_id
     AND queue_entry_id = p_queue_entry_id
     AND deleted_at IS NULL;
  IF v_count >= 10 THEN
    RAISE EXCEPTION 'Evidence attachment limit reached.'
      USING ERRCODE = 'P0001', DETAIL = 'IntegrityException';
  END IF;

  INSERT INTO public.dispute_evidence_attachments
    (organization_id, queue_entry_id, storage_path, file_name, mime_type,
     file_size_bytes, sha256_hash, verification_status, uploaded_by, attached_at)
  VALUES
    (p_organization_id, p_queue_entry_id, p_storage_path, p_file_name, p_mime_type,
     p_file_size_bytes, p_sha256_hash, 'PENDING', v_user, p_attached_at_utc)
  RETURNING id INTO v_id;

  -- ADD-1: independent audit fact per upload.
  INSERT INTO public.sla_audit_ledger_v2
    (organization_id, type, operator_id, set_id, contract_id, plan_version, payload, occurred_at_utc)
  VALUES (
    p_organization_id, 'DISPUTE_EVIDENCE_ATTACHED', v_user::text,
    v_queue.set_id, v_queue.contract_id::uuid, 0,
    jsonb_build_object(
      'queue_entry_id', p_queue_entry_id,
      'attachment_id',  v_id,
      'sha256_hash',    p_sha256_hash,
      'file_name',      p_file_name,
      'uploaded_by',    v_user
    ),
    p_attached_at_utc
  );

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.attach_dispute_evidence(
  UUID, UUID, TEXT, TEXT, TEXT, BIGINT, TEXT, UUID, TIMESTAMPTZ)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.attach_dispute_evidence(
  UUID, UUID, TEXT, TEXT, TEXT, BIGINT, TEXT, UUID, TIMESTAMPTZ)
  TO authenticated;
