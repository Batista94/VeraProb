-- =============================================================================
-- Migration: portal_token_scope — Sprint A (Portal Submissão + De Acordo) M1
-- Purpose:   Extends dispute_portal_tokens with a privilege scope (read|submit)
--            and a per-token submission cap, so the same tokenized portal can
--            both serve evidence (read) and accept counter-evidence (submit).
--
--            Also widens the read precondition of generate_dispute_portal_token
--            to include the 'applied' queue status — without this the "De Acordo"
--            (acknowledgement) flow is unreachable, since acknowledgement happens
--            after a sanction is applied, not while it is disputed.
--
-- Pattern:   Mirrors generate_dispute_portal_token. New columns are SEALED
--            (immutable after insert) — added to prevent_dpt_immutable_mutation.
--            submit > read in privilege: submit-token generation is TENANT_ADMIN
--            only (AUDITOR is excluded) and still requires an active dispute.
--
-- Council: Architect ✅ · Senior ✅ · QA-Security ✅ · Business ✅ · Lead ✅
-- Invariants: INV-1, INV-2, INV-3, INV-6, INV-22, INV-26, INV-DATA-API-GRANT.
-- Depends on: 20260814000002 (token table), 20260814000003 (read RPC).
-- =============================================================================

SET client_min_messages TO 'WARNING';

-- ── 1. Scope + submission-cap columns ────────────────────────────────────────
-- ADD COLUMN with a conforming constant DEFAULT is metadata-only (no rewrite);
-- the inline CHECK is satisfied by the default on every existing row.

ALTER TABLE public.dispute_portal_tokens
  ADD COLUMN IF NOT EXISTS token_scope TEXT NOT NULL DEFAULT 'read'
    CONSTRAINT chk_dpt_scope CHECK (token_scope IN ('read', 'submit'));

ALTER TABLE public.dispute_portal_tokens
  ADD COLUMN IF NOT EXISTS max_submissions INT NOT NULL DEFAULT 5
    CONSTRAINT chk_dpt_max_sub CHECK (max_submissions BETWEEN 1 AND 20);

COMMENT ON COLUMN public.dispute_portal_tokens.token_scope IS
  'Privilege scope: read (evidence + acknowledgement) or submit (counter-evidence upload). Sealed (INV-3).';
COMMENT ON COLUMN public.dispute_portal_tokens.max_submissions IS
  'Per-token counter-evidence submission cap (availability ceiling). Sealed (INV-3).';

-- ── 2. Seal new columns in the immutability trigger (INV-3) ──────────────────
-- token_scope and max_submissions are set once at creation and never change.

CREATE OR REPLACE FUNCTION public.prevent_dpt_immutable_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  -- Sealed forensic fields can never change.
  IF NEW.organization_id    IS DISTINCT FROM OLD.organization_id    OR
     NEW.queue_entry_id     IS DISTINCT FROM OLD.queue_entry_id     OR
     NEW.token              IS DISTINCT FROM OLD.token              OR
     NEW.created_by_user_id IS DISTINCT FROM OLD.created_by_user_id OR
     NEW.expires_at_utc     IS DISTINCT FROM OLD.expires_at_utc     OR
     NEW.created_at_utc     IS DISTINCT FROM OLD.created_at_utc     OR
     NEW.max_access_count   IS DISTINCT FROM OLD.max_access_count   OR
     NEW.token_scope        IS DISTINCT FROM OLD.token_scope        OR
     NEW.max_submissions    IS DISTINCT FROM OLD.max_submissions
  THEN
    RAISE EXCEPTION
      'dispute_portal_tokens: immutable field mutation (INV-3). id: %', OLD.id
    USING ERRCODE = 'restrict_violation';
  END IF;

  -- accessed_at_utc: NULL → timestamp once (never reset, never re-stamp).
  IF OLD.accessed_at_utc IS NOT NULL AND
     NEW.accessed_at_utc IS DISTINCT FROM OLD.accessed_at_utc
  THEN
    RAISE EXCEPTION
      'dispute_portal_tokens: accessed_at_utc already stamped (INV-3). id: %', OLD.id
    USING ERRCODE = 'restrict_violation';
  END IF;

  -- access_count: monotonic increment only (never decrease).
  IF NEW.access_count < OLD.access_count THEN
    RAISE EXCEPTION
      'dispute_portal_tokens: access_count cannot decrease (INV-3). id: %', OLD.id
    USING ERRCODE = 'restrict_violation';
  END IF;

  -- revoked_at_utc: NULL → timestamp once (never un-revoke, never re-stamp).
  IF OLD.revoked_at_utc IS NOT NULL AND
     NEW.revoked_at_utc IS DISTINCT FROM OLD.revoked_at_utc
  THEN
    RAISE EXCEPTION
      'dispute_portal_tokens: revoked_at_utc already stamped (INV-3). id: %', OLD.id
    USING ERRCODE = 'restrict_violation';
  END IF;

  RETURN NEW;
END;
$$;

-- ── 3. Widen read precondition: 'applied' OR 'disputed' ──────────────────────
-- A read token must be issuable once a sanction is applied (acknowledgement /
-- "De Acordo" flow) — not only while disputed. Submit tokens (next RPC) keep
-- the stricter 'disputed' gate. Signature unchanged (no PostgREST param drift).

CREATE OR REPLACE FUNCTION public.generate_dispute_portal_token(
  p_organization_id   UUID,
  p_queue_entry_id    UUID,
  p_created_by        UUID,
  p_expires_hours     INT DEFAULT 24,
  p_max_access_count  INT DEFAULT 5
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
  v_token    UUID;
  v_id       UUID;
  v_now      TIMESTAMPTZ := NOW();
BEGIN
  v_jwt_org := auth.jwt() -> 'app_metadata' ->> 'org_id';
  IF v_jwt_org IS NULL OR v_jwt_org::uuid <> p_organization_id THEN
    RAISE EXCEPTION 'Portal token rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  v_jwt_role := auth.jwt() -> 'app_metadata' ->> 'role';
  IF v_jwt_role IS NULL OR v_jwt_role NOT IN ('TENANT_ADMIN', 'AUDITOR') THEN
    RAISE EXCEPTION 'Portal token rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  v_user := (auth.jwt() ->> 'sub')::uuid;
  IF v_user IS NULL OR v_user <> p_created_by THEN
    RAISE EXCEPTION 'Portal token rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF p_expires_hours < 1 OR p_expires_hours > 48 THEN
    RAISE EXCEPTION 'Portal token rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_max_access_count < 1 OR p_max_access_count > 50 THEN
    RAISE EXCEPTION 'Portal token rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended(p_organization_id::text || ':' || p_queue_entry_id::text, 0)
  );

  -- Read tokens are valid for an applied or disputed sanction (acknowledgement
  -- needs an applied sanction; evidence review needs a disputed one).
  SELECT * INTO v_queue
    FROM public.sanction_review_queue
   WHERE id = p_queue_entry_id AND organization_id = p_organization_id
   FOR SHARE;
  IF NOT FOUND OR v_queue.status NOT IN ('applied', 'disputed') THEN
    RAISE EXCEPTION 'Portal token rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  INSERT INTO public.dispute_portal_tokens
    (organization_id, queue_entry_id, created_by_user_id,
     expires_at_utc, max_access_count, token_scope, created_at_utc)
  VALUES
    (p_organization_id, p_queue_entry_id, v_user,
     v_now + make_interval(hours => p_expires_hours),
     p_max_access_count, 'read', v_now)
  RETURNING id, token INTO v_id, v_token;

  INSERT INTO public.sla_audit_ledger_v2
    (organization_id, type, operator_id, set_id, contract_id, plan_version, payload, occurred_at_utc)
  VALUES (
    p_organization_id, 'DISPUTE_PORTAL_TOKEN_GENERATED', v_user::text,
    v_queue.set_id, v_queue.contract_id::uuid, 0,
    jsonb_build_object(
      'queue_entry_id', p_queue_entry_id,
      'token_id', v_id,
      'created_by', v_user,
      'token_scope', 'read',
      'expires_hours', p_expires_hours,
      'max_access_count', p_max_access_count
    ),
    v_now
  );

  RETURN v_token;
END;
$$;

REVOKE ALL ON FUNCTION public.generate_dispute_portal_token(UUID, UUID, UUID, INT, INT)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.generate_dispute_portal_token(UUID, UUID, UUID, INT, INT)
  TO authenticated;

-- ── 4. RPC: generate_portal_submit_token (TENANT_ADMIN only) ─────────────────
-- Issues a submit-scoped token allowing a carrier to upload counter-evidence.
-- submit > read in privilege: AUDITOR is excluded, and the dispute must be
-- active ('disputed'). Reuses the DISPUTE_PORTAL_TOKEN_GENERATED ledger fact
-- with token_scope='submit' in the payload (no new ledger type needed).

CREATE OR REPLACE FUNCTION public.generate_portal_submit_token(
  p_organization_id   UUID,
  p_queue_entry_id    UUID,
  p_created_by        UUID,
  p_expires_hours     INT DEFAULT 24,
  p_max_access_count  INT DEFAULT 5,
  p_max_submissions   INT DEFAULT 5
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
  v_token    UUID;
  v_id       UUID;
  v_now      TIMESTAMPTZ := NOW();
BEGIN
  -- ── Auth (INV-1, INV-26: every failure → 42501, generic message) ───────────
  v_jwt_org := auth.jwt() -> 'app_metadata' ->> 'org_id';
  IF v_jwt_org IS NULL OR v_jwt_org::uuid <> p_organization_id THEN
    RAISE EXCEPTION 'Portal token rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  -- TENANT_ADMIN only — submit is more privileged than read.
  v_jwt_role := auth.jwt() -> 'app_metadata' ->> 'role';
  IF v_jwt_role IS NULL OR v_jwt_role <> 'TENANT_ADMIN' THEN
    RAISE EXCEPTION 'Portal token rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  v_user := (auth.jwt() ->> 'sub')::uuid;
  IF v_user IS NULL OR v_user <> p_created_by THEN
    RAISE EXCEPTION 'Portal token rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF p_expires_hours < 1 OR p_expires_hours > 48 THEN
    RAISE EXCEPTION 'Portal token rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_max_access_count < 1 OR p_max_access_count > 50 THEN
    RAISE EXCEPTION 'Portal token rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_max_submissions < 1 OR p_max_submissions > 20 THEN
    RAISE EXCEPTION 'Portal token rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended(p_organization_id::text || ':' || p_queue_entry_id::text, 0)
  );

  -- Submit requires an active dispute (stricter than the read gate).
  SELECT * INTO v_queue
    FROM public.sanction_review_queue
   WHERE id = p_queue_entry_id AND organization_id = p_organization_id
   FOR SHARE;
  IF NOT FOUND OR v_queue.status <> 'disputed' THEN
    RAISE EXCEPTION 'Portal token rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  INSERT INTO public.dispute_portal_tokens
    (organization_id, queue_entry_id, created_by_user_id,
     expires_at_utc, max_access_count, token_scope, max_submissions, created_at_utc)
  VALUES
    (p_organization_id, p_queue_entry_id, v_user,
     v_now + make_interval(hours => p_expires_hours),
     p_max_access_count, 'submit', p_max_submissions, v_now)
  RETURNING id, token INTO v_id, v_token;

  INSERT INTO public.sla_audit_ledger_v2
    (organization_id, type, operator_id, set_id, contract_id, plan_version, payload, occurred_at_utc)
  VALUES (
    p_organization_id, 'DISPUTE_PORTAL_TOKEN_GENERATED', v_user::text,
    v_queue.set_id, v_queue.contract_id::uuid, 0,
    jsonb_build_object(
      'queue_entry_id', p_queue_entry_id,
      'token_id', v_id,
      'created_by', v_user,
      'token_scope', 'submit',
      'expires_hours', p_expires_hours,
      'max_access_count', p_max_access_count,
      'max_submissions', p_max_submissions
    ),
    v_now
  );

  RETURN v_token;
END;
$$;

REVOKE ALL ON FUNCTION public.generate_portal_submit_token(UUID, UUID, UUID, INT, INT, INT)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.generate_portal_submit_token(UUID, UUID, UUID, INT, INT, INT)
  TO authenticated;

RESET client_min_messages;
