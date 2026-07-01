-- =============================================================================
-- Migration: Webhook Endpoints
-- INV-22: Tenant Isolation
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.webhook_endpoints (
  id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id  UUID        NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  url              TEXT        NOT NULL CHECK (url LIKE 'https://%'),
  last_kick_at     TIMESTAMPTZ,
  is_active        BOOLEAN     NOT NULL DEFAULT true,
  deleted_at       TIMESTAMPTZ,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- RLS
ALTER TABLE public.webhook_endpoints ENABLE ROW LEVEL SECURITY;

-- Grants (Data API constraint)
GRANT SELECT, INSERT, UPDATE ON public.webhook_endpoints TO authenticated;
-- Dispatcher (service_role) reads endpoints for drain + updates last_kick_at rate-limit
GRANT SELECT, UPDATE ON public.webhook_endpoints TO service_role;

CREATE POLICY "Tenant Admins can manage webhook endpoints"
  ON public.webhook_endpoints
  AS PERMISSIVE
  FOR ALL
  TO authenticated
  USING (
    organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid
    AND (auth.jwt() -> 'app_metadata' ->> 'role') = 'TENANT_ADMIN'
  )
  WITH CHECK (
    organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid
    AND (auth.jwt() -> 'app_metadata' ->> 'role') = 'TENANT_ADMIN'
  );

COMMENT ON TABLE public.webhook_endpoints IS 'Configured webhook destinations per organization.';
