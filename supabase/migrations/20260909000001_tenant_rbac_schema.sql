-- =============================================================================
-- Migration: 20260909000001 — Tenant-customizable RBAC schema (Pilar 1.1)
--
-- Tables: tenant_permissions (global dictionary), tenant_roles,
--         tenant_role_permissions, user_tenant_roles, role_change_requests.
-- RLS: org-scoped SELECT via JWT; writes denied to authenticated (RPC-only).
-- Invariants: INV-1, INV-2, INV-3, INV-22, INV-26, INV-DATA-API-GRANT.
-- =============================================================================

SET client_min_messages TO 'WARNING';

-- ── 1. Global permission dictionary (Global Catalog RLS Pattern) ────────────
-- organization_id NULL = global catalog row (visible to all tenants).
-- Non-NULL = org-private extension (INV-22). SSOT: dispute_reason_codes.
CREATE TABLE public.tenant_permissions (
  key             TEXT        PRIMARY KEY,
  module          TEXT        NOT NULL,
  action          TEXT        NOT NULL,
  label_pt        TEXT        NOT NULL,
  description     TEXT        NOT NULL DEFAULT '',
  is_sensitive    BOOLEAN     NOT NULL DEFAULT false,
  is_scopable     BOOLEAN     NOT NULL DEFAULT false,
  organization_id UUID        REFERENCES public.organizations(id),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.tenant_permissions IS
  'Global Catalog RLS Pattern: organization_id NULL = shared permission dictionary; '
  'non-NULL = org-private extension. Client DML denied — mutations via RPC only.';

-- ── 2. Tenant-defined roles ─────────────────────────────────────────────────
CREATE TABLE public.tenant_roles (
  id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id  UUID        NOT NULL REFERENCES public.organizations(id),
  name             TEXT        NOT NULL,
  description      TEXT,
  is_system        BOOLEAN     NOT NULL DEFAULT false,
  created_by       UUID,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at       TIMESTAMPTZ,
  CONSTRAINT uq_tenant_roles_org_name UNIQUE (organization_id, name)
);

CREATE INDEX idx_tenant_roles_org_active
  ON public.tenant_roles (organization_id)
  WHERE deleted_at IS NULL;

-- ── 3. Role ↔ permission junction (ABAC-lite scope) ───────────────────────
CREATE TABLE public.tenant_role_permissions (
  tenant_role_id   UUID NOT NULL REFERENCES public.tenant_roles(id) ON DELETE CASCADE,
  permission_key   TEXT NOT NULL REFERENCES public.tenant_permissions(key),
  scope            JSONB,
  PRIMARY KEY (tenant_role_id, permission_key),
  CONSTRAINT chk_trp_scope_shape CHECK (
    scope IS NULL
    OR (
      jsonb_typeof(scope) = 'object'
      AND (
        NOT (scope ? 'contract_ids')
        OR (
          jsonb_typeof(scope -> 'contract_ids') = 'array'
          AND jsonb_array_length(scope -> 'contract_ids') <= 32
        )
      )
    )
  )
);

CREATE INDEX idx_tenant_role_permissions_role
  ON public.tenant_role_permissions (tenant_role_id);

-- ── 4. Multi-role user assignments (time-bound + soft revoke) ───────────────
CREATE TABLE public.user_tenant_roles (
  user_id          UUID NOT NULL,
  tenant_role_id   UUID NOT NULL REFERENCES public.tenant_roles(id),
  organization_id  UUID NOT NULL REFERENCES public.organizations(id),
  valid_from       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  valid_until      TIMESTAMPTZ,
  granted_by       UUID,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  revoked_at       TIMESTAMPTZ,
  PRIMARY KEY (user_id, tenant_role_id)
);

CREATE INDEX idx_user_tenant_roles_user_active
  ON public.user_tenant_roles (user_id, organization_id)
  WHERE revoked_at IS NULL;

CREATE INDEX idx_user_tenant_roles_role
  ON public.user_tenant_roles (tenant_role_id);

-- ── 5. Four-eyes approval queue (append-only payload; status via RPC) ───────
CREATE TABLE public.role_change_requests (
  id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id  UUID        NOT NULL REFERENCES public.organizations(id),
  request_type     TEXT        NOT NULL
    CHECK (request_type IN ('GRANT_ROLE', 'UPDATE_ROLE_PERMISSIONS', 'CREATE_ROLE')),
  payload          JSONB       NOT NULL,
  requested_by     UUID        NOT NULL,
  status           TEXT        NOT NULL DEFAULT 'PENDING'
    CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED', 'EXPIRED')),
  decided_by       UUID,
  decided_at       TIMESTAMPTZ,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_rcr_no_self_approval
    CHECK (decided_by IS NULL OR decided_by IS DISTINCT FROM requested_by)
);

CREATE INDEX idx_role_change_requests_org_pending
  ON public.role_change_requests (organization_id, created_at DESC)
  WHERE status = 'PENDING';

-- ── 6. Bump tenant_roles.updated_at when permissions change (feeds perms_v) ───
CREATE OR REPLACE FUNCTION public._touch_tenant_role_on_permission_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_role_id UUID;
BEGIN
  v_role_id := COALESCE(NEW.tenant_role_id, OLD.tenant_role_id);
  UPDATE public.tenant_roles
     SET updated_at = NOW()
   WHERE id = v_role_id;
  RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE TRIGGER trg_touch_tenant_role_on_permission_change
  AFTER INSERT OR UPDATE OR DELETE ON public.tenant_role_permissions
  FOR EACH ROW
  EXECUTE FUNCTION public._touch_tenant_role_on_permission_change();

-- ── 7. Seed global permission dictionary (append-only; new keys = new migration)
INSERT INTO public.tenant_permissions
  (key, module, action, label_pt, description, is_sensitive, is_scopable)
VALUES
  ('financial:read',   'financial',  'read',   'Ler financeiro',        'Visualizar dados financeiros do tenant',              false, true),
  ('financial:export', 'financial',  'export', 'Exportar financeiro',   'Exportar relatórios financeiros (ação sensível)',     true,  false),
  ('sla:read',         'sla',        'read',   'Ler sanções',           'Visualizar fila de sanções e vereditos',              false, false),
  ('sla:approve',      'sla',        'approve','Aprovar sanções',       'Aprovar ou rejeitar sanções (ação sensível)',         true,  false),
  ('contracts:read',   'contracts',  'read',   'Ler contratos',         'Visualizar contratos do tenant',                      false, true),
  ('contracts:write',  'contracts',  'write',  'Editar contratos',      'Criar e editar contratos',                            false, true),
  ('telemetry:read',   'telemetry',  'read',   'Ler telemetria',        'Visualizar telemetria operacional',                   false, false),
  ('cadastros:read',   'cadastros',  'read',   'Ler cadastros',         'Visualizar cadastros (motoristas, veículos, zonas)',  false, false),
  ('cadastros:write',  'cadastros',  'write',  'Editar cadastros',      'Criar e editar cadastros operacionais',               false, false),
  ('roles:manage',     'roles',      'manage', 'Gerenciar acessos',     'Criar perfis e atribuir permissões (ação sensível)',  true,  false);

-- ── 8. Row Level Security ───────────────────────────────────────────────────
ALTER TABLE public.tenant_permissions     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tenant_roles             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tenant_role_permissions  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_tenant_roles        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.role_change_requests     ENABLE ROW LEVEL SECURITY;

-- Global catalog + org-private extensions (never USING(true) — scanner + INV-22).
CREATE POLICY tenant_permissions_select_authenticated
  ON public.tenant_permissions
  FOR SELECT TO authenticated
  USING (
    organization_id IS NULL
    OR organization_id::text = auth.jwt() ->> 'organization_id'
  );

-- Org-scoped tables: INV-2 via top-level organization_id claim.
CREATE POLICY tenant_roles_select_org
  ON public.tenant_roles
  FOR SELECT TO authenticated
  USING (
    deleted_at IS NULL
    AND organization_id::text = auth.jwt() ->> 'organization_id'
  );

CREATE POLICY tenant_role_permissions_select_org
  ON public.tenant_role_permissions
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1
        FROM public.tenant_roles tr
       WHERE tr.id = tenant_role_permissions.tenant_role_id
         AND tr.deleted_at IS NULL
         AND tr.organization_id::text = auth.jwt() ->> 'organization_id'
    )
  );

CREATE POLICY user_tenant_roles_select_org
  ON public.user_tenant_roles
  FOR SELECT TO authenticated
  USING (organization_id::text = auth.jwt() ->> 'organization_id');

CREATE POLICY role_change_requests_select_org
  ON public.role_change_requests
  FOR SELECT TO authenticated
  USING (organization_id::text = auth.jwt() ->> 'organization_id');

-- ── 9. Explicit API grants (INV-DATA-API-GRANT) ─────────────────────────────
GRANT SELECT ON public.tenant_permissions    TO authenticated;
GRANT SELECT ON public.tenant_roles          TO authenticated;
GRANT SELECT ON public.tenant_role_permissions TO authenticated;
GRANT SELECT ON public.user_tenant_roles     TO authenticated;
GRANT SELECT ON public.role_change_requests  TO authenticated;

GRANT ALL ON public.tenant_permissions       TO service_role;
GRANT ALL ON public.tenant_roles             TO service_role;
GRANT ALL ON public.tenant_role_permissions  TO service_role;
GRANT ALL ON public.user_tenant_roles        TO service_role;
GRANT ALL ON public.role_change_requests     TO service_role;

-- ── 10. Trust-root hardening: client DML denied (writes only via RPC) ────────
REVOKE INSERT, UPDATE, DELETE ON public.tenant_roles            FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.tenant_role_permissions FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.user_tenant_roles       FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.role_change_requests    FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.tenant_permissions      FROM authenticated;
