-- =============================================================================
-- Migration: Add default tenant roles (Administrador, Validador, Auditor, Operador)
-- =============================================================================
-- Context: 
-- In new organizations, the access profiles tab was starting empty. 
-- The Council defined 4 default Tier-1 Enterprise profiles to be created:
-- 1. Administrador (Full access)
-- 2. Validador (Operational leadership, SLA approval, user management, no system configs)
-- 3. Auditor (Compliance, Read-Only, can export financial)
-- 4. Operador (Daily operations, no financial view, no SLA approval)
--
-- Actions:
-- 1. Create a helper function `_seed_default_tenant_roles(p_org_id)`
-- 2. Retroactively run the helper function for all existing organizations
-- 3. Update `super_admin_create_organization` to call this helper on creation
--
-- Invariants:
-- INV-DB: Append-only schema change. `super_admin_create_organization` is 
-- replaced completely and the old one overridden.
-- =============================================================================

-- ── 1. Helper function to seed roles ─────────────────────────────────────────

CREATE OR REPLACE FUNCTION public._seed_default_tenant_roles(p_org_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, extensions
AS $$
DECLARE
  v_admin_id UUID;
  v_validador_id UUID;
  v_auditor_id UUID;
  v_operador_id UUID;
BEGIN
  -- 1. Administrador
  INSERT INTO public.tenant_roles (organization_id, name, description, is_system)
  VALUES (p_org_id, 'Administrador', 'Acesso total e irrestrito, incluindo gestão de configurações e acessos.', true)
  ON CONFLICT (organization_id, name) DO NOTHING
  RETURNING id INTO v_admin_id;

  IF v_admin_id IS NULL THEN
    SELECT id INTO v_admin_id FROM public.tenant_roles WHERE organization_id = p_org_id AND name = 'Administrador';
  END IF;

  INSERT INTO public.tenant_role_permissions (tenant_role_id, permission_key)
  SELECT v_admin_id, key FROM public.tenant_permissions
  ON CONFLICT DO NOTHING;

  -- 2. Validador
  INSERT INTO public.tenant_roles (organization_id, name, description, is_system)
  VALUES (p_org_id, 'Validador', 'Visão executiva e poder de julgamento (aprovação de sanções), sem acesso a configurações sistêmicas.', true)
  ON CONFLICT (organization_id, name) DO NOTHING
  RETURNING id INTO v_validador_id;

  IF v_validador_id IS NULL THEN
    SELECT id INTO v_validador_id FROM public.tenant_roles WHERE organization_id = p_org_id AND name = 'Validador';
  END IF;

  INSERT INTO public.tenant_role_permissions (tenant_role_id, permission_key)
  SELECT v_validador_id, key FROM public.tenant_permissions
  WHERE key IN ('financial:read', 'financial:export', 'sla:read', 'sla:approve', 'contracts:read', 'contracts:write', 'telemetry:read', 'cadastros:read', 'cadastros:write', 'users:manage', 'roles:read')
  ON CONFLICT DO NOTHING;

  -- 3. Auditor
  INSERT INTO public.tenant_roles (organization_id, name, description, is_system)
  VALUES (p_org_id, 'Auditor', 'Perfil read-only para compliance. Pode auditar dados e exportar financeiros, mas não realiza operações.', true)
  ON CONFLICT (organization_id, name) DO NOTHING
  RETURNING id INTO v_auditor_id;

  IF v_auditor_id IS NULL THEN
    SELECT id INTO v_auditor_id FROM public.tenant_roles WHERE organization_id = p_org_id AND name = 'Auditor';
  END IF;

  INSERT INTO public.tenant_role_permissions (tenant_role_id, permission_key)
  SELECT v_auditor_id, key FROM public.tenant_permissions
  WHERE key IN ('financial:read', 'financial:export', 'sla:read', 'telemetry:read', 'cadastros:read', 'roles:read')
  ON CONFLICT DO NOTHING;

  -- 4. Operador
  INSERT INTO public.tenant_roles (organization_id, name, description, is_system)
  VALUES (p_org_id, 'Operador', 'Acesso operacional. Pode gerenciar cadastros e contratos, mas não possui visão executiva nem poder de julgar sanções.', true)
  ON CONFLICT (organization_id, name) DO NOTHING
  RETURNING id INTO v_operador_id;

  IF v_operador_id IS NULL THEN
    SELECT id INTO v_operador_id FROM public.tenant_roles WHERE organization_id = p_org_id AND name = 'Operador';
  END IF;

  INSERT INTO public.tenant_role_permissions (tenant_role_id, permission_key)
  SELECT v_operador_id, key FROM public.tenant_permissions
  WHERE key IN ('sla:read', 'contracts:read', 'contracts:write', 'telemetry:read', 'cadastros:read', 'cadastros:write')
  ON CONFLICT DO NOTHING;
END;
$$;

-- Do not allow API access to the helper
REVOKE ALL ON FUNCTION public._seed_default_tenant_roles(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._seed_default_tenant_roles(UUID) FROM authenticated;

-- ── 2. Retroactively seed existing organizations ──────────────────────────────

DO $$
DECLARE
  v_org_id UUID;
BEGIN
  FOR v_org_id IN SELECT id FROM public.organizations LOOP
    PERFORM public._seed_default_tenant_roles(v_org_id);
  END LOOP;
END;
$$;

-- ── 3. Update super_admin_create_organization to use the helper ─────────────

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

  -- ── Seed default tenant roles ───────────────────────────────────────────────
  PERFORM public._seed_default_tenant_roles(v_org_id);

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

REVOKE ALL ON FUNCTION public.super_admin_create_organization(
  TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, INT, INT, UUID,
  JSONB, INT, INT, INT, TEXT, TEXT, TEXT, TEXT, text[]
) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.super_admin_create_organization(
  TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, INT, INT, UUID,
  JSONB, INT, INT, INT, TEXT, TEXT, TEXT, TEXT, text[]
) TO authenticated;
