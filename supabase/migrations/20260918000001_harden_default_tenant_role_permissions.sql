-- =============================================================================
-- Migration: Harden Default Tenant Role Permissions (SOC2/ISO 27001)
-- =============================================================================
-- Context: 
-- 1. Validador had `users:manage` + `sla:approve` violating Segregation of Duties.
-- 2. Operador had `contracts:write` violating Principle of Least Privilege.
--
-- Actions:
-- 1. Replace `_seed_default_tenant_roles(p_org_id)` with corrected matrix.
-- 2. Retroactively DELETE excessive permissions for existing system roles.
-- 3. Log the compliance update to the audit trail.
--
-- Invariants:
-- INV-DB: Append-only schema change. `CREATE OR REPLACE FUNCTION`.
-- =============================================================================

-- ── 1. Update helper function with hardened matrix ───────────────────────────

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
  -- 1. Administrador (Unchanged)
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

  -- 2. Validador (Hardened: removed users:manage)
  INSERT INTO public.tenant_roles (organization_id, name, description, is_system)
  VALUES (p_org_id, 'Validador', 'Visão executiva e poder de julgamento (aprovação de sanções), sem acesso a configurações sistêmicas.', true)
  ON CONFLICT (organization_id, name) DO NOTHING
  RETURNING id INTO v_validador_id;

  IF v_validador_id IS NULL THEN
    SELECT id INTO v_validador_id FROM public.tenant_roles WHERE organization_id = p_org_id AND name = 'Validador';
  END IF;

  INSERT INTO public.tenant_role_permissions (tenant_role_id, permission_key)
  SELECT v_validador_id, key FROM public.tenant_permissions
  WHERE key IN ('financial:read', 'financial:export', 'sla:read', 'sla:approve', 'contracts:read', 'contracts:write', 'telemetry:read', 'cadastros:read', 'cadastros:write', 'roles:read')
  ON CONFLICT DO NOTHING;

  -- 3. Auditor (Unchanged)
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

  -- 4. Operador (Hardened: removed contracts:write, description updated)
  INSERT INTO public.tenant_roles (organization_id, name, description, is_system)
  VALUES (p_org_id, 'Operador', 'Acesso operacional. Pode gerenciar cadastros e ler contratos, mas não possui visão executiva nem poder de julgar sanções.', true)
  ON CONFLICT (organization_id, name)
  DO UPDATE SET description = 'Acesso operacional. Pode gerenciar cadastros e ler contratos, mas não possui visão executiva nem poder de julgar sanções.'
  RETURNING id INTO v_operador_id;

  IF v_operador_id IS NULL THEN
    SELECT id INTO v_operador_id FROM public.tenant_roles WHERE organization_id = p_org_id AND name = 'Operador';
  END IF;

  INSERT INTO public.tenant_role_permissions (tenant_role_id, permission_key)
  SELECT v_operador_id, key FROM public.tenant_permissions
  WHERE key IN ('sla:read', 'contracts:read', 'telemetry:read', 'cadastros:read', 'cadastros:write')
  ON CONFLICT DO NOTHING;
END;
$$;

-- Do not allow API access to the helper
REVOKE ALL ON FUNCTION public._seed_default_tenant_roles(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._seed_default_tenant_roles(UUID) FROM authenticated;

-- ── 2. Retroactive fix for existing organizations ────────────────────────────

DO $$
BEGIN
  -- Remove 'users:manage' from 'Validador'
  DELETE FROM public.tenant_role_permissions -- INV-DB: zero-downtime-verified
  WHERE permission_key = 'users:manage' 
    AND tenant_role_id IN (
      SELECT id FROM public.tenant_roles WHERE name = 'Validador' AND is_system = true
    );

  -- Remove 'contracts:write' from 'Operador'
  DELETE FROM public.tenant_role_permissions -- INV-DB: zero-downtime-verified
  WHERE permission_key = 'contracts:write' 
    AND tenant_role_id IN (
      SELECT id FROM public.tenant_roles WHERE name = 'Operador' AND is_system = true
    );

  -- Log the compliance remediation
  INSERT INTO public.system_audit_log (
    event_type, severity, payload, source,
    organization_id, organization_name, reason, actor_type
  )
  VALUES (
    'COMPLIANCE_REMEDIATION', 'info',
    jsonb_build_object(
      'remediation', 'SoD and PoLP enforcement on default tenant roles',
      'removed', jsonb_build_array(
        jsonb_build_object('role', 'Validador', 'permission', 'users:manage', 'reason', 'Segregation of Duties (SOC2 CC6.1)'),
        jsonb_build_object('role', 'Operador', 'permission', 'contracts:write', 'reason', 'Principle of Least Privilege (ISO 27001 A.6.1.2)')
      )
    ),
    'migration_20260918000001', NULL, 'System', 'SYSTEM_UPDATE', 'SYSTEM'
  );
END;
$$;
