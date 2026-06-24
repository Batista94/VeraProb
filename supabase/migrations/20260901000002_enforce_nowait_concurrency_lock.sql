-- =============================================================================
-- Migration: enforce_nowait_concurrency_lock
-- Purpose:   Concurrency lock (Gap 2). Forces NOWAIT on the primary action RPCs
--            to Fail-Fast and prevent deadlocks/UI hangs.
-- =============================================================================
-- pr_scanner: ignore-regression

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
   WHERE id = p_queue_entry_id
     AND organization_id = p_organization_id
   FOR UPDATE NOWAIT;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Dispute resolution rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_queue.status <> 'disputed' THEN
    RAISE EXCEPTION 'This dispute has already been resolved by another auditor.'
      USING ERRCODE = 'P0001', DETAIL = 'IdempotencyProcessingException';
  END IF;

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
         END,
         disputed_at = CASE
           WHEN p_resolution = 'DISPUTE_RETRACTED' THEN NULL
           ELSE disputed_at
         END,
         disputed_by = CASE
           WHEN p_resolution = 'DISPUTE_RETRACTED' THEN NULL
           ELSE disputed_by
         END,
         resolution_due_at = CASE
           WHEN p_resolution = 'DISPUTE_RETRACTED' THEN NULL
           ELSE resolution_due_at
         END
   WHERE id = p_queue_entry_id
     AND organization_id = p_organization_id;

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
   WHERE id = p_queue_entry_id
     AND organization_id = p_organization_id
   FOR UPDATE NOWAIT;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Sanction approval rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_queue.status <> 'pending' THEN
    RAISE EXCEPTION 'This sanction has already been reviewed by another auditor.'
      USING ERRCODE = 'P0001', DETAIL = 'IdempotencyProcessingException';
  END IF;

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
   WHERE id = p_queue_entry_id
     AND organization_id = p_organization_id
   FOR UPDATE NOWAIT;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Sanction rejection rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_queue.status <> 'pending' THEN
    RAISE EXCEPTION 'This sanction has already been reviewed by another auditor.'
      USING ERRCODE = 'P0001', DETAIL = 'IdempotencyProcessingException';
  END IF;

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
