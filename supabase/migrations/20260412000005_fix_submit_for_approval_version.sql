-- ============================================================
-- veraprob — Fix submit_contract_for_approval RPC: add version check
-- ============================================================
-- REASON:
--   The original RPC did not verify the contract version before
--   transitioning status. This allowed a user to submit a stale
--   contract (modified by another user between load and submit).
--
-- FIX:
--   Add p_expected_version parameter. The UPDATE now includes
--   AND version = p_expected_version, which:
--   - Ensures atomic optimistic locking within the RPC
--   - Prevents stale submissions silently succeeding
--   - Is consistent with INV-32 (Optimistic Locking)
-- ============================================================

CREATE OR REPLACE FUNCTION public.submit_contract_for_approval(
  p_contract_id      UUID,
  p_token_id         UUID,
  p_token            TEXT,
  p_expires_at       TIMESTAMPTZ,
  p_expected_version BIGINT DEFAULT NULL  -- NULL = skip check (backward compat)
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  caller_org_id  UUID;
  caller_role    TEXT;
  rows_updated   INT;
BEGIN
  caller_org_id := (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid;
  caller_role   := auth.jwt() -> 'app_metadata' ->> 'role';

  IF caller_org_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: no organization context in JWT';
  END IF;

  IF caller_role != 'TENANT_ADMIN' THEN
    RAISE EXCEPTION 'Unauthorized: TENANT_ADMIN role required';
  END IF;

  -- INV-32: Optimistic lock — only update if version matches
  UPDATE public.contracts
  SET
    status                        = 'awaitingContractorAcceptance',
    submitted_for_approval_at_utc = now()
  WHERE id              = p_contract_id
    AND organization_id = caller_org_id
    AND status          = 'draft'
    AND (p_expected_version IS NULL OR version = p_expected_version);

  GET DIAGNOSTICS rows_updated = ROW_COUNT;

  IF rows_updated = 0 THEN
    -- Determine WHY it failed for a better error message
    IF p_expected_version IS NOT NULL THEN
      -- Version mismatch — concurrent modification
      RAISE EXCEPTION
        'Contract % was modified by another user (expected version %, but current version differs). '
        'Please reload and try again.',
        p_contract_id,
        p_expected_version;
    ELSE
      -- Not found or not in draft status
      RAISE EXCEPTION
        'Contract not found in draft status for this organization. ID: %',
        p_contract_id;
    END IF;
  END IF;

  INSERT INTO public.contract_review_tokens
    (id, contract_id, organization_id, token, expires_at_utc)
  VALUES
    (p_token_id, p_contract_id, caller_org_id, p_token, p_expires_at);
END;
$$;

-- Keep existing grants
REVOKE ALL ON FUNCTION public.submit_contract_for_approval(UUID, UUID, TEXT, TIMESTAMPTZ, BIGINT)
  FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.submit_contract_for_approval(UUID, UUID, TEXT, TIMESTAMPTZ, BIGINT)
  TO authenticated;
