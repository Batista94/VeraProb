-- =============================================================================
-- Migration: dispute_portal_tokens — Forensic Dispute Portal (Item 5.3)
-- Purpose:   Tokenized read-only portal for external parties. A short-lived
--            URL token grants access to a dispute's evidence snapshot without
--            requiring core authentication. Kills "I never saw the evidence."
--
-- Pattern:   Follows justification_submission_tokens (Phase 9.8.J) idiom:
--            append-only, immutability trigger, SECURITY DEFINER RPCs.
--
-- Differences from justification_submission_tokens:
--   - Multi-access with cap (max N reads) vs single-use
--   - Admin revocation (revoked_at_utc)
--   - Shorter TTL (max 48h vs 72h)
--
-- Council: Architect ✅ · Senior ✅ · QA-Security ✅ · Business ✅ · Lead ✅
-- Invariants: INV-1, INV-2, INV-3, INV-6, INV-9, INV-22, INV-26, INV-DB.
-- =============================================================================

-- Suppress DROP TRIGGER/POLICY IF EXISTS NOTICEs (objects don't exist on fresh reset).
SET client_min_messages TO 'WARNING';

-- ── 1. Table ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.dispute_portal_tokens (
  id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id     UUID        NOT NULL REFERENCES public.organizations(id),
  queue_entry_id      UUID        NOT NULL REFERENCES public.sanction_review_queue(id),

  -- UUID v4 as URL credential — 128-bit space (collision infeasible).
  token               UUID        NOT NULL UNIQUE DEFAULT gen_random_uuid(),

  -- Actor provenance
  created_by_user_id  UUID        NOT NULL,

  -- TTL: 1–48 hours (short-lived — evidence links shouldn't persist).
  expires_at_utc      TIMESTAMPTZ NOT NULL
    CONSTRAINT chk_dpt_expires_window CHECK (
      expires_at_utc > created_at_utc
      AND expires_at_utc <= created_at_utc + INTERVAL '48 hours'
    ),

  -- Access tracking: multi-use with cap (not single-use like justification tokens).
  -- accessed_at_utc: first access stamp (NULL → timestamp once, never reset).
  accessed_at_utc     TIMESTAMPTZ,
  access_count        INT         NOT NULL DEFAULT 0
    CONSTRAINT chk_dpt_access_count_non_neg CHECK (access_count >= 0),
  max_access_count    INT         NOT NULL DEFAULT 5
    CONSTRAINT chk_dpt_max_access CHECK (max_access_count BETWEEN 1 AND 50),

  -- Admin revocation (NULL → timestamp once, never reset). Senior amendment.
  revoked_at_utc      TIMESTAMPTZ,

  created_at_utc      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.dispute_portal_tokens IS
  'deny-all: Tokenized read-only portal tokens. service_role only (validated via SECURITY DEFINER RPCs).';

-- ── Indexes ───────────────────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_dpt_token
  ON public.dispute_portal_tokens (token);

CREATE INDEX IF NOT EXISTS idx_dpt_org_queue
  ON public.dispute_portal_tokens (organization_id, queue_entry_id)
  WHERE revoked_at_utc IS NULL;

-- ── Immutability trigger (INV-3) ─────────────────────────────────────────────
-- Sealed fields: org_id, queue_entry_id, token, created_by, expires_at, created_at, max_access_count.
-- Mutable: accessed_at_utc (NULL→ts once), access_count (monotonic), revoked_at_utc (NULL→ts once).

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
     NEW.max_access_count   IS DISTINCT FROM OLD.max_access_count
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

DROP TRIGGER IF EXISTS trg_dpt_no_immutable_update ON public.dispute_portal_tokens;
CREATE TRIGGER trg_dpt_no_immutable_update
  BEFORE UPDATE ON public.dispute_portal_tokens
  FOR EACH ROW EXECUTE FUNCTION public.prevent_dpt_immutable_mutation();

-- ── Block DELETE (append-only, INV-3) ────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.prevent_dpt_delete()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION
    'dispute_portal_tokens is append-only (INV-3). DELETE blocked. id: %', OLD.id
  USING ERRCODE = 'restrict_violation';
END;
$$;

DROP TRIGGER IF EXISTS trg_dpt_no_delete ON public.dispute_portal_tokens;
CREATE TRIGGER trg_dpt_no_delete
  BEFORE DELETE ON public.dispute_portal_tokens
  FOR EACH ROW EXECUTE FUNCTION public.prevent_dpt_delete();

-- ── RLS (INV-2): deny-all to anon/authenticated — service_role only ──────────

ALTER TABLE public.dispute_portal_tokens ENABLE ROW LEVEL SECURITY;

-- No SELECT/INSERT/UPDATE/DELETE policies for anon or authenticated.
-- Service_role bypasses RLS. RPCs are SECURITY DEFINER.

-- ── Grants (INV-DATA-API-GRANT) ──────────────────────────────────────────────
-- Deny-all table. Only service_role has access (via SECURITY DEFINER RPCs).
REVOKE ALL ON TABLE public.dispute_portal_tokens FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.dispute_portal_tokens TO service_role;

-- ── 2. RPC: generate_dispute_portal_token ────────────────────────────────────
-- Creates a tokenized portal link for an external party to view dispute evidence.
-- Authenticated TENANT_ADMIN / AUDITOR only.
-- Advisory lock prevents concurrent duplicate tokens for the same dispute.

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
  -- ── Auth (INV-1, INV-26: every failure → 42501, generic message) ────────────
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

  -- ── Validate TTL window ─────────────────────────────────────────────────────
  IF p_expires_hours < 1 OR p_expires_hours > 48 THEN
    RAISE EXCEPTION 'Portal token rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_max_access_count < 1 OR p_max_access_count > 50 THEN
    RAISE EXCEPTION 'Portal token rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- ── Advisory lock: serialize token creation per dispute (prevent duplicates) ─
  -- Single-bigint overload: there is no pg_advisory_xact_lock(bigint, bigint).
  -- Combine org + queue into one key (collision-immaterial: lock scope only).
  PERFORM pg_advisory_xact_lock(
    hashtextextended(p_organization_id::text || ':' || p_queue_entry_id::text, 0)
  );

  -- ── Ownership + state: queue must belong to org and be disputed ──────────────
  SELECT * INTO v_queue
    FROM public.sanction_review_queue
   WHERE id = p_queue_entry_id AND organization_id = p_organization_id
   FOR SHARE;
  IF NOT FOUND OR v_queue.status <> 'disputed' THEN
    RAISE EXCEPTION 'Portal token rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- ── Insert token row ────────────────────────────────────────────────────────
  INSERT INTO public.dispute_portal_tokens
    (organization_id, queue_entry_id, created_by_user_id,
     expires_at_utc, max_access_count, created_at_utc)
  VALUES
    (p_organization_id, p_queue_entry_id, v_user,
     v_now + make_interval(hours => p_expires_hours),
     p_max_access_count, v_now)
  RETURNING id, token INTO v_id, v_token;

  -- ── Ledger fact: DISPUTE_PORTAL_TOKEN_GENERATED (INV-3) ─────────────────────
  INSERT INTO public.sla_audit_ledger_v2
    (organization_id, type, operator_id, set_id, contract_id, plan_version, payload, occurred_at_utc)
  VALUES (
    p_organization_id, 'DISPUTE_PORTAL_TOKEN_GENERATED', v_user::text,
    v_queue.set_id, v_queue.contract_id::uuid, 0,
    jsonb_build_object(
      'queue_entry_id', p_queue_entry_id,
      'token_id', v_id,
      'created_by', v_user,
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

-- ── 3. RPC: revoke_dispute_portal_token ──────────────────────────────────────
-- Admin-only revocation. Stamps revoked_at_utc (NULL → timestamp once).

CREATE OR REPLACE FUNCTION public.revoke_dispute_portal_token(
  p_organization_id UUID,
  p_token_id        UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_jwt_org  TEXT;
  v_jwt_role TEXT;
  v_user     UUID;
  v_row      public.dispute_portal_tokens;
  v_queue    public.sanction_review_queue;
  v_now      TIMESTAMPTZ := NOW();
BEGIN
  -- ── Auth (INV-1, INV-26) ────────────────────────────────────────────────────
  v_jwt_org := auth.jwt() -> 'app_metadata' ->> 'org_id';
  IF v_jwt_org IS NULL OR v_jwt_org::uuid <> p_organization_id THEN
    RAISE EXCEPTION 'Portal token rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  v_jwt_role := auth.jwt() -> 'app_metadata' ->> 'role';
  IF v_jwt_role IS NULL OR v_jwt_role <> 'TENANT_ADMIN' THEN
    RAISE EXCEPTION 'Portal token rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  v_user := (auth.jwt() ->> 'sub')::uuid;
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Portal token rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- ── Load + lock the token row ───────────────────────────────────────────────
  SELECT * INTO v_row
    FROM public.dispute_portal_tokens
   WHERE id = p_token_id AND organization_id = p_organization_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Portal token rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF v_row.revoked_at_utc IS NOT NULL THEN
    -- Already revoked — idempotent, no error.
    RETURN;
  END IF;

  -- ── Stamp revocation ────────────────────────────────────────────────────────
  UPDATE public.dispute_portal_tokens
     SET revoked_at_utc = v_now
   WHERE id = p_token_id AND organization_id = p_organization_id;

  -- ── Ledger fact: DISPUTE_PORTAL_TOKEN_REVOKED (INV-3) ───────────────────────
  SELECT * INTO v_queue FROM public.sanction_review_queue
   WHERE id = v_row.queue_entry_id AND organization_id = p_organization_id;

  INSERT INTO public.sla_audit_ledger_v2
    (organization_id, type, operator_id, set_id, contract_id, plan_version, payload, occurred_at_utc)
  VALUES (
    p_organization_id, 'DISPUTE_PORTAL_TOKEN_REVOKED', v_user::text,
    v_queue.set_id, v_queue.contract_id::uuid, 0,
    jsonb_build_object(
      'queue_entry_id', v_row.queue_entry_id,
      'token_id', v_row.id,
      'revoked_by', v_user,
      'access_count_at_revocation', v_row.access_count
    ),
    v_now
  );
END;
$$;

REVOKE ALL ON FUNCTION public.revoke_dispute_portal_token(UUID, UUID)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.revoke_dispute_portal_token(UUID, UUID)
  TO authenticated;

-- Reset client_min_messages.
RESET client_min_messages;
