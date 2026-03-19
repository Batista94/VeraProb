-- ============================================================
-- veraprob — Phase 6 Block 6: Contract Approval Workflow
-- Sprint 6.6 | 2026-03-21
-- ============================================================
-- Changes:
--   1. contracts: add submitted_for_approval_at_utc column
--   2. contracts: fix status CHECK to include 'awaitingContractorAcceptance'
--   3. CREATE TABLE contract_review_tokens (token-based public review link)
--   4. RPC: submit_contract_for_approval (TENANT_ADMIN only, atomic)
--   5. RPC: accept_contract_by_contractor (anon+authenticated, token = auth)
--   6. RPC: get_contract_for_review (anon+authenticated, public read)
-- ============================================================

-- ── 1a. Add submitted_for_approval_at_utc column ─────────────────────────────
ALTER TABLE public.contracts
  ADD COLUMN IF NOT EXISTS submitted_for_approval_at_utc TIMESTAMPTZ;

-- ── 1b. Fix status CHECK constraint ──────────────────────────────────────────
-- Original constraint (20260310000000) only covered: draft, active, closed
-- Must drop and recreate to add 'awaitingContractorAcceptance'
ALTER TABLE public.contracts
  DROP CONSTRAINT IF EXISTS contracts_status_check;

ALTER TABLE public.contracts
  ADD CONSTRAINT contracts_status_check
  CHECK (status IN (
    'draft',
    'awaitingContractorAcceptance',
    'active',
    'closed'
  ));

-- ── 2. contract_review_tokens table ──────────────────────────────────────────
CREATE TABLE public.contract_review_tokens (
  id               UUID        PRIMARY KEY,
  contract_id      UUID        NOT NULL REFERENCES public.contracts(id) ON DELETE CASCADE,
  organization_id  UUID        NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  token            TEXT        NOT NULL UNIQUE,
  created_at_utc   TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at_utc   TIMESTAMPTZ NOT NULL,
  used_at_utc      TIMESTAMPTZ,

  CONSTRAINT token_not_empty CHECK (trim(token) <> '')
);

CREATE INDEX idx_crt_token    ON public.contract_review_tokens (token);
CREATE INDEX idx_crt_contract ON public.contract_review_tokens (contract_id);

-- RLS
ALTER TABLE public.contract_review_tokens ENABLE ROW LEVEL SECURITY;

-- Tenant admins: full access scoped to their org
CREATE POLICY "Tenant Isolation: contract_review_tokens"
  ON public.contract_review_tokens
  FOR ALL TO authenticated
  USING (
    organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid
    AND (auth.jwt() -> 'app_metadata' ->> 'role') = 'TENANT_ADMIN'
  )
  WITH CHECK (
    organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid
    AND (auth.jwt() -> 'app_metadata' ->> 'role') = 'TENANT_ADMIN'
  );

-- Public: SELECT active (non-expired, non-used) tokens for the review page
-- No org check needed — token possession is the authority
CREATE POLICY "Public token read"
  ON public.contract_review_tokens
  FOR SELECT TO anon, authenticated
  USING (used_at_utc IS NULL AND expires_at_utc > now());

-- ── 3. RPC: submit_contract_for_approval ────────────────────────────────────
-- Authenticated TENANT_ADMIN only.
-- Atomically transitions contract draft → awaitingContractorAcceptance
-- and inserts a review token.
-- INV-7: token generated in Dart and passed as p_token (not generated here).
CREATE OR REPLACE FUNCTION public.submit_contract_for_approval(
  p_contract_id  UUID,
  p_token_id     UUID,
  p_token        TEXT,
  p_expires_at   TIMESTAMPTZ
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  caller_org_id UUID;
  caller_role   TEXT;
  rows_updated  INT;
BEGIN
  caller_org_id := (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid;
  caller_role   := auth.jwt() -> 'app_metadata' ->> 'role';

  IF caller_org_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: no organization context in JWT';
  END IF;

  IF caller_role != 'TENANT_ADMIN' THEN
    RAISE EXCEPTION 'Unauthorized: TENANT_ADMIN role required';
  END IF;

  UPDATE public.contracts
  SET
    status                        = 'awaitingContractorAcceptance',
    submitted_for_approval_at_utc = now()
  WHERE id              = p_contract_id
    AND organization_id = caller_org_id
    AND status          = 'draft';

  GET DIAGNOSTICS rows_updated = ROW_COUNT;

  IF rows_updated = 0 THEN
    RAISE EXCEPTION
      'Contract not found in draft status for this organization. ID: %',
      p_contract_id;
  END IF;

  INSERT INTO public.contract_review_tokens
    (id, contract_id, organization_id, token, expires_at_utc)
  VALUES
    (p_token_id, p_contract_id, caller_org_id, p_token, p_expires_at);
END;
$$;

REVOKE ALL ON FUNCTION public.submit_contract_for_approval(UUID, UUID, TEXT, TIMESTAMPTZ)
  FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.submit_contract_for_approval(UUID, UUID, TEXT, TIMESTAMPTZ)
  TO authenticated;

-- ── 4. RPC: accept_contract_by_contractor ───────────────────────────────────
-- Public (anon + authenticated). Token IS the authorization.
-- Atomically:
--   1. Locks token row (FOR UPDATE — prevents race conditions)
--   2. Validates token not expired/used
--   3. Marks token used_at_utc = now() (immutable — no DELETE, INV-1)
--   4. Transitions contract awaitingContractorAcceptance → active
-- Returns JSONB { contract_id, organization_id } for Dart ledger append.
CREATE OR REPLACE FUNCTION public.accept_contract_by_contractor(
  p_token TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_token       public.contract_review_tokens%ROWTYPE;
  rows_updated  INT;
BEGIN
  IF p_token IS NULL OR trim(p_token) = '' THEN
    RAISE EXCEPTION 'Token cannot be empty';
  END IF;

  -- Lock token row to prevent concurrent double-acceptance
  SELECT * INTO v_token
  FROM public.contract_review_tokens
  WHERE token         = p_token
    AND used_at_utc   IS NULL
    AND expires_at_utc > now()
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Review token not found, expired, or already used';
  END IF;

  -- Mark token consumed (INV-1: stamp, do not delete)
  UPDATE public.contract_review_tokens
  SET used_at_utc = now()
  WHERE id = v_token.id;

  -- Transition contract to active
  UPDATE public.contracts
  SET
    status           = 'active',
    activated_at_utc = now()
  WHERE id              = v_token.contract_id
    AND organization_id = v_token.organization_id
    AND status          = 'awaitingContractorAcceptance';

  GET DIAGNOSTICS rows_updated = ROW_COUNT;

  IF rows_updated = 0 THEN
    RAISE EXCEPTION
      'Contract not in awaitingContractorAcceptance state. Possible data inconsistency. Contract ID: %',
      v_token.contract_id;
  END IF;

  RETURN jsonb_build_object(
    'contract_id',     v_token.contract_id,
    'organization_id', v_token.organization_id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.accept_contract_by_contractor(TEXT) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.accept_contract_by_contractor(TEXT) TO anon, authenticated;

-- ── 5. RPC: get_contract_for_review ─────────────────────────────────────────
-- Public (anon + authenticated). No Supabase auth required.
-- Returns contract summary for the review page.
-- Only works while token is active AND contract is awaiting acceptance.
CREATE OR REPLACE FUNCTION public.get_contract_for_review(
  p_token TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_result JSONB;
BEGIN
  IF p_token IS NULL OR trim(p_token) = '' THEN
    RAISE EXCEPTION 'Token cannot be empty';
  END IF;

  SELECT jsonb_build_object(
    'contract_id',             c.id,
    'name',                    c.name,
    'contractor_name',         c.contractor_name,
    'valid_from_utc',          c.valid_from_utc,
    'valid_until_utc',         c.valid_until_utc,
    'financial_ceiling_cents', c.financial_ceiling_cents,
    'status',                  c.status,
    'organization_id',         c.organization_id
  )
  INTO v_result
  FROM public.contract_review_tokens t
  JOIN public.contracts c ON c.id = t.contract_id
  WHERE t.token         = p_token
    AND t.used_at_utc   IS NULL
    AND t.expires_at_utc > now()
    AND c.status        = 'awaitingContractorAcceptance';

  IF v_result IS NULL THEN
    RAISE EXCEPTION
      'Review link not found, expired, or contract no longer awaiting acceptance';
  END IF;

  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.get_contract_for_review(TEXT) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.get_contract_for_review(TEXT) TO anon, authenticated;
