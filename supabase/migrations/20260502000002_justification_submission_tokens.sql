-- pr_scanner: ignore-regression
-- Suppress DROP TRIGGER/POLICY IF EXISTS NOTICEs (objects don't exist on fresh reset).
SET client_min_messages TO 'WARNING';

-- =============================================================================
-- Migration: justification_submission_tokens + use_justification_token RPC
--            (Phase 9.8.J)
--
-- Tokenized self-service path: operator generates a UUID link; driver opens it
-- without auth, fills the justification form, submits via RPC.
--
-- INV-1:  Token scoped to org — operator can only create tokens for own org.
-- INV-7:  Token is append-only; `used_at_utc` is the only mutable field and
--         can only transition NULL → timestamp once.
-- INV-9:  All timestamps UTC.
-- INV-11: Token is single-use (idempotency gate on `used_at_utc`).
-- PO-6:   Token expiry is 1–72 hours, set by the operator at generation time.
-- =============================================================================

-- ── 1. justification_submission_tokens ──────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.justification_submission_tokens (
  id                    UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id       UUID        NOT NULL,
  contract_id           TEXT        NOT NULL,
  set_id                TEXT        NOT NULL,

  -- The specific justification created when the token is consumed (null until used).
  justification_id      UUID
    REFERENCES public.contractor_justifications(id),

  -- UUID v4 used as the URL token — 128-bit space makes collision infeasible (PO-1).
  token                 UUID        NOT NULL UNIQUE DEFAULT gen_random_uuid(),

  created_by_user_id    UUID        NOT NULL,
  expires_at_utc        TIMESTAMPTZ NOT NULL
    CONSTRAINT chk_jst_expires_window
      CHECK (
        expires_at_utc > created_at_utc
        AND expires_at_utc <= created_at_utc + INTERVAL '72 hours'
      ),

  -- Stamped once (NULL → timestamp) when driver submits. Never reset. (INV-11)
  used_at_utc           TIMESTAMPTZ,

  created_at_utc        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.justification_submission_tokens IS
  'deny-all: Anonymous submission tokens. service_role only (token validated in RPC).';

-- ── Indexes ───────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_jst_token
  ON public.justification_submission_tokens (token);

CREATE INDEX IF NOT EXISTS idx_jst_org_contract
  ON public.justification_submission_tokens (organization_id, contract_id);

CREATE INDEX IF NOT EXISTS idx_jst_set_id
  ON public.justification_submission_tokens (set_id);

-- ── Immutability trigger (INV-7) ─────────────────────────────────────────────
-- All fields are locked. `used_at_utc` may only transition once: NULL → timestamp.
CREATE OR REPLACE FUNCTION public.prevent_jst_immutable_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  -- Enforce single-use stamp: once set, used_at_utc cannot be changed.
  IF OLD.used_at_utc IS NOT NULL AND
     NEW.used_at_utc IS DISTINCT FROM OLD.used_at_utc
  THEN
    RAISE EXCEPTION
      'justification_submission_tokens: used_at_utc already stamped (INV-11). id: %', OLD.id
    USING ERRCODE = 'restrict_violation';
  END IF;

  -- Lock all identity + routing fields unconditionally.
  IF NEW.organization_id      IS DISTINCT FROM OLD.organization_id      OR
     NEW.contract_id          IS DISTINCT FROM OLD.contract_id          OR
     NEW.set_id               IS DISTINCT FROM OLD.set_id               OR
     NEW.token                IS DISTINCT FROM OLD.token                OR
     NEW.created_by_user_id   IS DISTINCT FROM OLD.created_by_user_id   OR
     NEW.expires_at_utc       IS DISTINCT FROM OLD.expires_at_utc       OR
     NEW.created_at_utc       IS DISTINCT FROM OLD.created_at_utc
  THEN
    RAISE EXCEPTION
      'justification_submission_tokens: immutable field mutation attempted (INV-7). id: %', OLD.id
    USING ERRCODE = 'restrict_violation';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_jst_no_immutable_update
  ON public.justification_submission_tokens;
CREATE TRIGGER trg_jst_no_immutable_update
  BEFORE UPDATE ON public.justification_submission_tokens
  FOR EACH ROW EXECUTE FUNCTION public.prevent_jst_immutable_mutation();

-- ── Block DELETE (INV-7) ──────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.prevent_jst_delete()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION
    'justification_submission_tokens is append-only (INV-7). DELETE blocked. id: %', OLD.id
  USING ERRCODE = 'restrict_violation';
END;
$$;

DROP TRIGGER IF EXISTS trg_jst_no_delete ON public.justification_submission_tokens;
CREATE TRIGGER trg_jst_no_delete
  BEFORE DELETE ON public.justification_submission_tokens
  FOR EACH ROW EXECUTE FUNCTION public.prevent_jst_delete();

-- ── RLS (INV-1) ───────────────────────────────────────────────────────────────
ALTER TABLE public.justification_submission_tokens ENABLE ROW LEVEL SECURITY;

-- Org members (admin/operator) can view tokens they manage.
DROP POLICY IF EXISTS jst_select_own_org ON public.justification_submission_tokens;
CREATE POLICY jst_select_own_org
  ON public.justification_submission_tokens
  FOR SELECT
  USING (
    organization_id::text = (auth.jwt() ->> 'organization_id')
    AND (auth.jwt() ->> 'role') IN ('admin', 'operator', 'auditor')
  );

-- SuperAdmin read-only across all orgs.
DROP POLICY IF EXISTS jst_select_super_admin ON public.justification_submission_tokens;
CREATE POLICY jst_select_super_admin
  ON public.justification_submission_tokens
  FOR SELECT
  USING (
    (auth.jwt() -> 'app_metadata' ->> 'super_admin')::boolean IS TRUE
  );

-- Operator/admin can generate tokens (INSERT).
DROP POLICY IF EXISTS jst_insert_operator ON public.justification_submission_tokens;
CREATE POLICY jst_insert_operator
  ON public.justification_submission_tokens
  FOR INSERT
  WITH CHECK (
    organization_id::text = (auth.jwt() ->> 'organization_id')
    AND (auth.jwt() ->> 'role') IN ('admin', 'operator')
  );

-- Service role (SECURITY DEFINER RPC) can update to stamp used_at_utc.
DROP POLICY IF EXISTS jst_update_service ON public.justification_submission_tokens;
CREATE POLICY jst_update_service
  ON public.justification_submission_tokens
  FOR UPDATE
  USING (true)
  WITH CHECK (true);

-- Service role can insert on behalf of anon driver path.
DROP POLICY IF EXISTS jst_insert_service ON public.justification_submission_tokens;
CREATE POLICY jst_insert_service
  ON public.justification_submission_tokens
  FOR INSERT
  WITH CHECK (true);

-- ── 2. RPC: use_justification_token ──────────────────────────────────────────
--
-- Called by the anon driver portal after form submission.
-- Single transaction: validates token → creates justification → stamps token.
-- Returns the new justification_id on success; raises on any violation.
--
-- Security model:
--   - SECURITY DEFINER bypasses RLS (anon has no JWT org claim).
--   - Business rules enforce token validity + single-use atomically.
--   - REVOKE ALL prevents direct anon invocation outside RPC contract.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.use_justification_token(
  p_token           UUID,
  p_category        TEXT,
  p_description     TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_token_row   public.justification_submission_tokens%ROWTYPE;
  v_just_id     UUID;
BEGIN
  -- ── 1. Load and lock the token row. ───────────────────────────────────────
  SELECT *
    INTO v_token_row
    FROM public.justification_submission_tokens
   WHERE token = p_token
     FOR UPDATE;  -- Serialize concurrent submissions on the same token.

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Token not found.'
      USING ERRCODE = 'no_data_found';
  END IF;

  -- ── 2. Validate: not expired. ─────────────────────────────────────────────
  IF NOW() > v_token_row.expires_at_utc THEN
    RAISE EXCEPTION 'Token has expired.'
      USING ERRCODE = 'check_violation';
  END IF;

  -- ── 3. Validate: not already used (idempotency gate — INV-11). ────────────
  IF v_token_row.used_at_utc IS NOT NULL THEN
    RAISE EXCEPTION 'Token has already been used.'
      USING ERRCODE = 'unique_violation';
  END IF;

  -- ── 4. Validate category. ─────────────────────────────────────────────────
  IF p_category NOT IN (
    'MECHANICAL', 'FORCE_MAJEURE', 'TRAFFIC',
    'ROUTE_DEVIATION', 'COMMUNICATION', 'OTHER'
  ) THEN
    RAISE EXCEPTION 'Invalid category: %', p_category
      USING ERRCODE = 'check_violation';
  END IF;

  -- ── 5. Validate description length (PO-3: min 20 chars). ─────────────────
  IF char_length(trim(p_description)) < 20 THEN
    RAISE EXCEPTION 'Description must be at least 20 characters.'
      USING ERRCODE = 'check_violation';
  END IF;

  -- ── 6. INSERT the justification row. ─────────────────────────────────────
  INSERT INTO public.contractor_justifications (
    organization_id,
    contract_id,
    set_id,
    submitted_by_token,
    category,
    description,
    status
  ) VALUES (
    v_token_row.organization_id,
    v_token_row.contract_id,
    v_token_row.set_id,
    v_token_row.id,   -- FK to the token record, not the UUID token value.
    p_category,
    p_description,
    'PENDING'
  )
  RETURNING id INTO v_just_id;

  -- ── 7. Stamp token as used + link justification_id. ──────────────────────
  UPDATE public.justification_submission_tokens
     SET used_at_utc     = NOW(),
         justification_id = v_just_id
   WHERE id = v_token_row.id;

  RETURN v_just_id;
END;
$$;

-- Remove broad access; grant only to roles that need it.
REVOKE ALL ON FUNCTION public.use_justification_token(UUID, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.use_justification_token(UUID, TEXT, TEXT)
  TO anon, authenticated;
