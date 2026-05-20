-- =============================================================================
-- Migration: Add extensions schema to search_path for organization creation (INV-DB)
-- =============================================================================
-- Problem: secret generation was a separate HTTP call to Edge Function
-- generate-org-secret, which silently failed under AAL2/MFA in local envs.
--
-- Fix: generate secret atomically inside super_admin_create_organization,
-- insert into org_api_secrets, and return the plaintext secret exactly once
-- in the result set. Plain-text is never stored.
--
-- INV-3:  org_api_secrets is append-only (immutability trigger already in place).
-- INV-6:  All datetimes TIMESTAMPTZ via NOW() (session is UTC-pinned).
-- INV-22: Secret bound to org UUID at creation — cross-tenant HMAC mismatch = quarantine.
-- INV-28: org secret generated atomically at creation. Plaintext returned once, hash stored.
-- =============================================================================

-- ── Guard: pgcrypto required for gen_random_bytes / digest (INV-28) ─────────
-- Idempotent. Supabase hosted pre-installs it; fresh local/CI envs (db reset)
-- may not. Declaring it here makes this migration self-contained regardless of
-- whether 20200101000000_enable_extensions.sql ran in the same session.
CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";

-- ── Step 1: Recreate function with new search_path including extensions ──────

CREATE OR REPLACE FUNCTION public.super_admin_create_organization(
  p_legal_name            TEXT,
  p_trade_name            TEXT,
  p_cnpj                  TEXT,
  p_timezone              TEXT,
  p_currency_code         TEXT,
  p_plan_type             TEXT,
  p_max_vehicles          INT,
  p_max_active_contracts  INT,
  p_super_admin_user_id   UUID,
  p_capabilities          JSONB    DEFAULT NULL,
  p_tool_cost_cents       INT      DEFAULT NULL,
  p_dwell_time_seconds    INT      DEFAULT 300,
  p_billing_day           INT      DEFAULT NULL,
  p_contact_email         TEXT     DEFAULT NULL,
  p_external_id           TEXT     DEFAULT NULL,
  p_reason                TEXT     DEFAULT NULL,
  p_organization_type     TEXT     DEFAULT NULL,
  p_allowed_domains       text[]   DEFAULT '{}'
)
RETURNS TABLE(org_id UUID, plaintext_secret TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, extensions
AS $fn$
DECLARE
  v_org_id         UUID := gen_random_uuid();
  v_actor_id       UUID;
  v_actor_type     TEXT;
  v_normalized     text[];
  v_raw_secret     TEXT;
  v_secret_hash    TEXT;
BEGIN
  -- ── JWT validation ──────────────────────────────────────────────────────────
  IF (auth.jwt() ->> 'sub') IS NOT NULL THEN
    IF (auth.jwt() -> 'app_metadata' ->> 'super_admin') IS DISTINCT FROM 'true' THEN
      RAISE EXCEPTION 'Unauthorized: super_admin claim required'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  -- ── Actor resolution ────────────────────────────────────────────────────────
  IF (auth.jwt() ->> 'sub') IS NOT NULL THEN
    v_actor_id   := (auth.jwt() ->> 'sub')::uuid;
    v_actor_type := 'HUMAN';
  ELSE
    v_actor_id   := p_super_admin_user_id;
    v_actor_type := 'SYSTEM';
  END IF;

  -- ── Input validation ────────────────────────────────────────────────────────
  IF p_legal_name IS NULL OR trim(p_legal_name) = '' THEN
    RAISE EXCEPTION 'legal_name cannot be empty';
  END IF;
  IF p_trade_name IS NULL OR trim(p_trade_name) = '' THEN
    RAISE EXCEPTION 'trade_name cannot be empty';
  END IF;
  IF p_plan_type NOT IN ('starter', 'professional', 'enterprise') THEN
    RAISE EXCEPTION 'Invalid plan_type: %. Must be starter, professional, or enterprise', p_plan_type;
  END IF;
  IF p_max_vehicles < 1 THEN
    RAISE EXCEPTION 'max_vehicles must be >= 1';
  END IF;
  IF p_max_active_contracts < 1 THEN
    RAISE EXCEPTION 'max_active_contracts must be >= 1';
  END IF;

  -- ── Normalize allowed_domains ───────────────────────────────────────────────
  SELECT ARRAY(
    SELECT DISTINCT lower(trim(d))
    FROM unnest(p_allowed_domains) AS d
    WHERE trim(d) <> ''
    ORDER BY lower(trim(d))
  ) INTO v_normalized;

  -- ── Insert organization ─────────────────────────────────────────────────────
  -- NOTE: is_active is GENERATED ALWAYS AS (status = 'ACTIVE') — do NOT insert.
  INSERT INTO public.organizations (
    id, name, legal_name, cnpj, timezone, currency_code,
    plan_type, max_vehicles, max_active_contracts, capabilities,
    tool_cost_cents, dwell_time_seconds, billing_day, contact_email,
    external_id, organization_type, allowed_domains
  )
  VALUES (
    v_org_id, p_trade_name, p_legal_name,
    CASE WHEN trim(p_cnpj) = '' THEN NULL ELSE trim(p_cnpj) END,
    p_timezone, p_currency_code, p_plan_type, p_max_vehicles,
    p_max_active_contracts,
    COALESCE(p_capabilities, '{"allows_sealing": true, "allows_loading": true, "allows_cargo_check": true, "allows_incident": true, "allows_doc": true, "smart_classify": true}'::jsonb),
    p_tool_cost_cents, p_dwell_time_seconds, p_billing_day,
    p_contact_email, p_external_id, p_organization_type, v_normalized
  );

  -- ── Billing event (INV-3) ───────────────────────────────────────────────────
  INSERT INTO public.tenant_billing_events (
    organization_id, event_type, new_plan, changed_by_super_admin_id,
    new_max_vehicles, new_max_contracts, reason, occurred_at_utc
  )
  VALUES (
    v_org_id, 'ORG_CREATED', p_plan_type, p_super_admin_user_id,
    p_max_vehicles, p_max_active_contracts, p_reason, NOW()
  );

  -- ── Generate and store org secret atomically (INV-28) ──────────────────────
  -- Plaintext derived from 32 cryptographically random bytes via pgcrypto.
  -- Only the SHA-256 hex digest is persisted; plaintext is returned once and discarded.
  v_raw_secret  := encode(extensions.gen_random_bytes(32), 'hex');
  v_secret_hash := encode(extensions.digest(v_raw_secret, 'sha256'), 'hex');

  INSERT INTO public.org_api_secrets (
    organization_id,
    secret_hash,
    version
  )
  VALUES (
    v_org_id,
    v_secret_hash,
    1
  );
  -- INV-28: org secret generated atomically at creation

  -- ── Audit log (INV-3) ──────────────────────────────────────────────────────
  INSERT INTO public.system_audit_log (
    event_type, severity, payload, source,
    organization_id, organization_name, reason, actor_type
  )
  VALUES (
    'ORGANIZATION_CREATE', 'info',
    jsonb_build_object(
      'before', '{}'::jsonb,
      'after', jsonb_build_object(
        'legal_name',         p_legal_name,
        'trade_name',         p_trade_name,
        'cnpj',              p_cnpj,
        'plan_type',         p_plan_type,
        'max_vehicles',      p_max_vehicles,
        'tool_cost_cents',   p_tool_cost_cents,
        'billing_day',       p_billing_day,
        'contact_email',     p_contact_email,
        'external_id',       p_external_id,
        'organization_type', p_organization_type,
        'allowed_domains',   v_normalized
      ),
      'actor_id', v_actor_id
    ),
    'super_admin_rpc', v_org_id, p_trade_name, p_reason, v_actor_type
  );

  -- ── Return org_id + plaintext_secret (shown once, never stored) ────────────
  RETURN QUERY SELECT v_org_id, v_raw_secret;
END;
$fn$;

-- ── Step 2: Permissions ───────────────────────────────────────────────────────
REVOKE ALL ON FUNCTION public.super_admin_create_organization(
  TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, INT, INT, UUID,
  JSONB, INT, INT, INT, TEXT, TEXT, TEXT, TEXT, text[]
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.super_admin_create_organization(
  TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, INT, INT, UUID,
  JSONB, INT, INT, INT, TEXT, TEXT, TEXT, TEXT, text[]
) TO authenticated;
