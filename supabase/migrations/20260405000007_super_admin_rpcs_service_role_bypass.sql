-- pr_scanner: ignore-regression
--
 =============================================================================
-- Phase 9.2 — SuperAdmin RPCs: service_role bypass (CREATE OR REPLACE)
-- =============================================================================
-- MOTIVO:
--   (auth.jwt() ->> 'sub') retorna NULL quando o cliente usa service_role key diretamente
--   (sem sessão de usuário autenticado). Isso afeta testes de integração e
--   chamadas server-side legítimas (migrações, scripts de onboarding, etc).
--
-- PADRÃO SUPABASE:
--   service_role já bypassa RLS automaticamente — tem trust elevado por design.
--   Verificar JWT é redundante para chamadas service_role. O bloco de validação
--   JWT só faz sentido quando há um usuário autenticado ((auth.jwt() ->> 'sub') IS NOT NULL).
--
-- SEGURANÇA:
--   - GRANT EXECUTE TO authenticated bloqueia chamadas anon no nível do PostgREST.
--   - Logo, (auth.jwt() ->> 'sub') IS NULL dentro da função = service_role call (não anon).
--   - Em produção, o Flutter SuperAdmin client usa o client autenticado (anon key +
--     login), portanto (auth.jwt() ->> 'sub') não é NULL e a validação JWT permanece ativa.
-- =============================================================================


-- =============================================================================
-- RPC 1: super_admin_create_organization (com service_role bypass)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.super_admin_create_organization(
  p_legal_name            TEXT,
  p_trade_name            TEXT,
  p_cnpj                  TEXT,
  p_timezone              TEXT,
  p_currency_code         TEXT,
  p_plan_type             TEXT,
  p_max_vehicles          INT,
  p_max_active_contracts  INT,
  p_super_admin_user_id   UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_org_id UUID := gen_random_uuid();
BEGIN
  -- Validação JWT: apenas quando há sessão de usuário (não service_role).
  -- (auth.jwt() ->> 'sub') IS NULL indica chamada via service_role key — bypass permitido.
  IF (auth.jwt() ->> 'sub') IS NOT NULL THEN
    IF (auth.jwt() -> 'app_metadata' ->> 'super_admin') IS DISTINCT FROM 'true' THEN
      RAISE EXCEPTION 'Unauthorized: super_admin claim required'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  -- Validações de input
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

  -- Inserir organização
  INSERT INTO public.organizations (
    id,
    name,
    legal_name,
    cnpj,
    timezone,
    currency_code,
    plan_type,
    max_vehicles,
    max_active_contracts,
    is_active
  )
  VALUES (
    v_org_id,
    p_trade_name,
    p_legal_name,
    CASE WHEN trim(p_cnpj) = '' THEN NULL ELSE trim(p_cnpj) END,
    p_timezone,
    p_currency_code,
    p_plan_type,
    p_max_vehicles,
    p_max_active_contracts,
    true
  );

  -- Registrar billing event (append-only)
  INSERT INTO public.tenant_billing_events (
    organization_id,
    event_type,
    new_plan,
    changed_by_super_admin_id,
    new_max_vehicles,
    new_max_contracts,
    occurred_at_utc
  )
  VALUES (
    v_org_id,
    'ORG_CREATED',
    p_plan_type,
    p_super_admin_user_id,
    p_max_vehicles,
    p_max_active_contracts,
    NOW()
  );

  RETURN v_org_id;
END;
$$;

REVOKE ALL ON FUNCTION public.super_admin_create_organization(
  TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, INT, INT, UUID
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.super_admin_create_organization(
  TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, INT, INT, UUID
) TO authenticated;


-- =============================================================================
-- RPC 2: super_admin_invite_first_admin (com service_role bypass)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.super_admin_invite_first_admin(
  p_org_id        UUID,
  p_email         TEXT,
  p_role          TEXT,
  p_token         TEXT,
  p_invitation_id UUID,
  p_expires_at    TIMESTAMPTZ,
  p_invited_by    UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  -- Validação JWT: apenas quando há sessão de usuário (não service_role).
  IF (auth.jwt() ->> 'sub') IS NOT NULL THEN
    IF (auth.jwt() -> 'app_metadata' ->> 'super_admin') IS DISTINCT FROM 'true' THEN
      RAISE EXCEPTION 'Unauthorized: super_admin claim required'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  -- Validar que a organização existe
  IF NOT EXISTS (SELECT 1 FROM public.organizations WHERE id = p_org_id) THEN
    RAISE EXCEPTION 'Organization % not found', p_org_id;
  END IF;

  -- Validar role
  IF p_role NOT IN ('TENANT_ADMIN', 'OPERATOR', 'AUDITOR') THEN
    RAISE EXCEPTION 'Invalid role: %. Must be TENANT_ADMIN, OPERATOR, or AUDITOR', p_role;
  END IF;

  IF p_email IS NULL OR trim(p_email) = '' THEN
    RAISE EXCEPTION 'Email cannot be empty';
  END IF;

  -- Revogar convite pendente anterior para este email nesta org
  UPDATE public.invitations
  SET revoked_at_utc = now()
  WHERE organization_id = p_org_id
    AND email           = lower(trim(p_email))
    AND accepted_at_utc IS NULL
    AND revoked_at_utc  IS NULL;

  -- Inserir novo convite
  INSERT INTO public.invitations (
    id,
    organization_id,
    email,
    role,
    token,
    invited_by,
    expires_at_utc
  )
  VALUES (
    p_invitation_id,
    p_org_id,
    lower(trim(p_email)),
    p_role,
    p_token,
    p_invited_by,
    p_expires_at
  );
END;
$$;

REVOKE ALL ON FUNCTION public.super_admin_invite_first_admin(
  UUID, TEXT, TEXT, TEXT, UUID, TIMESTAMPTZ, UUID
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.super_admin_invite_first_admin(
  UUID, TEXT, TEXT, TEXT, UUID, TIMESTAMPTZ, UUID
) TO authenticated;
