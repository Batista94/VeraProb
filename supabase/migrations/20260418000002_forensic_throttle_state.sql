--
-- Suppress DROP TRIGGER/POLICY IF EXISTS NOTICEs (objects don't exist on fresh reset).
SET client_min_messages TO 'WARNING';

-- =============================================================================
-- Migration: forensic_throttle_state + forensic_throttle_events (CX-05 v3.0)
--
-- Server-side authoritative throttle for forensic violations. When a client
-- submits a justification whose evidence trips the ContextualSignatureAnalyzer,
-- the application handler increments this table via SECURITY INVOKER RPCs.
-- The next submission is delayed via exponential backoff (2s/4s/8s, cap 10
-- consecutive failures). A modified client cannot bypass this limit — RLS
-- forces RPCs to run under the caller's JWT and tenant.
--
-- INV-1:  Fail-fast tenant claim match in every RPC body.
-- INV-2:  RLS via auth.jwt() ->> 'organization_id'.
-- INV-3:  forensic_throttle_events is APPEND-ONLY (UPDATE/DELETE trigger).
-- INV-16: Minimal indexed lookup — 1 SELECT + 0–1 INSERT per check (<10ms).
-- INV-18: Authority lives server-side; client SmartConcurrencyGovernor is UX.
-- INV-24: RPCs execute as SECURITY INVOKER so JWT claims govern access.
-- =============================================================================

-- ── 1. forensic_throttle_state (mutable operational state) ────────────────────

CREATE TABLE IF NOT EXISTS public.forensic_throttle_state (
  user_id               UUID        NOT NULL,
  organization_id       UUID        NOT NULL,
  consecutive_failures  INT         NOT NULL DEFAULT 0
    CONSTRAINT chk_fts_failures_nonneg CHECK (consecutive_failures >= 0),
  next_allowed_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, organization_id)
);

ALTER TABLE public.forensic_throttle_state ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS forensic_throttle_tenant_rls ON public.forensic_throttle_state;
CREATE POLICY forensic_throttle_tenant_rls ON public.forensic_throttle_state
  FOR ALL
  TO authenticated
  USING  (organization_id::text = auth.jwt() ->> 'organization_id')
  WITH CHECK (organization_id::text = auth.jwt() ->> 'organization_id');

CREATE INDEX IF NOT EXISTS idx_forensic_throttle_next_allowed
  ON public.forensic_throttle_state (next_allowed_at);

-- ── 2. forensic_throttle_events (append-only audit ledger, INV-3) ─────────────

CREATE TABLE IF NOT EXISTS public.forensic_throttle_events (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           UUID        NOT NULL,
  organization_id   UUID        NOT NULL,
  event_type        TEXT        NOT NULL
    CONSTRAINT chk_fte_event_type
      CHECK (event_type IN ('FAILURE', 'RESET', 'BLOCK')),
  occurred_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  metadata          JSONB
);

ALTER TABLE public.forensic_throttle_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS forensic_throttle_events_tenant_rls
  ON public.forensic_throttle_events;
CREATE POLICY forensic_throttle_events_tenant_rls
  ON public.forensic_throttle_events
  FOR SELECT
  TO authenticated
  USING (organization_id::text = auth.jwt() ->> 'organization_id');

CREATE INDEX IF NOT EXISTS idx_forensic_throttle_events_org_time
  ON public.forensic_throttle_events (organization_id, occurred_at DESC);

-- INV-3: block UPDATE/DELETE on the ledger.
CREATE OR REPLACE FUNCTION public.block_throttle_events_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION 'forensic_throttle_events is append-only (INV-3)'
    USING ERRCODE = '55000';
END;
$$;

DROP TRIGGER IF EXISTS tr_block_throttle_events_mutation
  ON public.forensic_throttle_events;
CREATE TRIGGER tr_block_throttle_events_mutation
  BEFORE UPDATE OR DELETE ON public.forensic_throttle_events
  FOR EACH ROW
  EXECUTE FUNCTION public.block_throttle_events_mutation();

-- ── 3. RPCs (SECURITY INVOKER, INV-1 fail-fast) ──────────────────────────────

CREATE OR REPLACE FUNCTION public.check_forensic_throttle(p_org_id UUID)
RETURNS TABLE(allowed BOOLEAN, wait_seconds INT)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_user  UUID := (auth.jwt() ->> 'sub')::uuid;
  v_claim UUID := (auth.jwt() ->> 'organization_id')::UUID;
  v_next  TIMESTAMPTZ;
BEGIN
  IF v_claim IS NULL OR v_claim <> p_org_id THEN
    RAISE EXCEPTION 'INV-1 tenant mismatch' USING ERRCODE = '42501';
  END IF;

  SELECT s.next_allowed_at
    INTO v_next
    FROM public.forensic_throttle_state s
    WHERE s.user_id = v_user AND s.organization_id = p_org_id;

  IF v_next IS NULL OR v_next <= NOW() THEN
    RETURN QUERY SELECT TRUE, 0;
  ELSE
    INSERT INTO public.forensic_throttle_events(
      user_id, organization_id, event_type, metadata
    )
    VALUES (
      v_user, p_org_id, 'BLOCK',
      jsonb_build_object('wait_s', CEIL(EXTRACT(EPOCH FROM (v_next - NOW())))::INT)
    );
    RETURN QUERY SELECT FALSE, CEIL(EXTRACT(EPOCH FROM (v_next - NOW())))::INT;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.record_forensic_failure(p_org_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_user  UUID := (auth.jwt() ->> 'sub')::uuid;
  v_claim UUID := (auth.jwt() ->> 'organization_id')::UUID;
BEGIN
  IF v_claim IS NULL OR v_claim <> p_org_id THEN
    RAISE EXCEPTION 'INV-1 tenant mismatch' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.forensic_throttle_state(
    user_id, organization_id, consecutive_failures, next_allowed_at, updated_at
  )
  VALUES (
    v_user, p_org_id, 1,
    NOW() + INTERVAL '2 seconds',
    NOW()
  )
  ON CONFLICT (user_id, organization_id) DO UPDATE
    SET consecutive_failures =
          LEAST(public.forensic_throttle_state.consecutive_failures + 1, 10),
        next_allowed_at =
          NOW() + (LEAST(
            POWER(
              2,
              LEAST(public.forensic_throttle_state.consecutive_failures + 1, 3)
            ),
            8
          ) * INTERVAL '1 second'),
        updated_at = NOW();

  INSERT INTO public.forensic_throttle_events(user_id, organization_id, event_type)
    VALUES (v_user, p_org_id, 'FAILURE');
END;
$$;

CREATE OR REPLACE FUNCTION public.reset_forensic_throttle(p_org_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_user  UUID := (auth.jwt() ->> 'sub')::uuid;
  v_claim UUID := (auth.jwt() ->> 'organization_id')::UUID;
BEGIN
  IF v_claim IS NULL OR v_claim <> p_org_id THEN
    RAISE EXCEPTION 'INV-1 tenant mismatch' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.forensic_throttle_state(
    user_id, organization_id, consecutive_failures, next_allowed_at, updated_at
  )
  VALUES (v_user, p_org_id, 0, NOW(), NOW())
  ON CONFLICT (user_id, organization_id) DO UPDATE
    SET consecutive_failures = 0,
        next_allowed_at = NOW(),
        updated_at = NOW();

  INSERT INTO public.forensic_throttle_events(user_id, organization_id, event_type)
    VALUES (v_user, p_org_id, 'RESET');
END;
$$;

-- ── 4. Grants (authenticated role executes RPCs under its own JWT) ───────────

GRANT EXECUTE ON FUNCTION public.check_forensic_throttle(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_forensic_failure(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reset_forensic_throttle(UUID)  TO authenticated;
