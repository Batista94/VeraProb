-- ============================================================
-- PactaFlow — Bootstrap Dev Seed
-- ============================================================
-- DEV ONLY — DO NOT execute in staging or production.
--
-- Seeds two bootstrap dev users as TENANT_ADMIN so the
-- custom_access_token_hook can inject org_id + role into
-- their JWTs. Without this, all RLS policies reject every
-- query (hook returns null for unknown users).
--
-- Role value MUST match the CHECK constraint in user_roles:
--   CHECK (role IN ('TENANT_ADMIN', 'OPERATOR', 'AUDITOR'))
--
-- Safe to re-run: ON CONFLICT (user_id) DO NOTHING.
-- ============================================================

INSERT INTO public.user_roles (user_id, organization_id, role)
VALUES
  (
    '09d00994-6b32-4df3-b08f-3d722f28f4d0',
    '00000000-0000-0000-0000-000000000001',
    'TENANT_ADMIN'
  ),
  (
    '210b892e-2f05-4eff-bb45-c3664141022b',
    '00000000-0000-0000-0000-000000000002',
    'TENANT_ADMIN'
  )
ON CONFLICT (user_id) DO NOTHING;
