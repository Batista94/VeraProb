-- =============================================================================
-- Phase 10: super_admin_update_allowed_domains RPC
-- =============================================================================
-- Allows a SuperAdmin to update the allowed_domains whitelist for an org.
-- Normalizes input (lowercase + array_distinct) server-side as defense-in-depth.
-- Appends immutable 'DOMAINS_UPDATED' billing event (INV-7 append-only).
--
-- INV-2:  authenticated role cannot UPDATE organizations directly.
--         This SECURITY DEFINER function is the only write path.
-- INV-7:  Billing event append-only — no UPDATE/DELETE.
-- INV-9:  occurred_at_utc uses NOW() (database UTC clock).
-- Service-role bypass: (auth.jwt() ->> 'sub') IS NULL = trusted server call.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.super_admin_update_allowed_domains(
  p_org_id              UUID,
  p_allowed_domains     text[],
  p_super_admin_user_id UUID,
  p_reason              TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_normalized text[];
BEGIN
  -- ── JWT validation ──────────────────────────────────────────────────────────
  IF (auth.jwt() ->> 'sub') IS NOT NULL THEN
    IF (auth.jwt() -> 'app_metadata' ->> 'super_admin') IS DISTINCT FROM 'true' THEN
      RAISE EXCEPTION 'Unauthorized: super_admin claim required'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  -- ── Organization must exist ─────────────────────────────────────────────────
  IF NOT EXISTS (SELECT 1 FROM public.organizations WHERE id = p_org_id) THEN
    RAISE EXCEPTION 'Organization % not found.', p_org_id;
  END IF;

  -- ── Normalize: lowercase + deduplicate (defense-in-depth) ──────────────────
  SELECT ARRAY(
    SELECT DISTINCT lower(trim(d))
    FROM unnest(p_allowed_domains) AS d
    WHERE trim(d) <> ''
    ORDER BY lower(trim(d))
  ) INTO v_normalized;

  -- ── Update organization ─────────────────────────────────────────────────────
  UPDATE public.organizations
     SET allowed_domains = v_normalized
   WHERE id = p_org_id;

  -- ── Append immutable audit event (INV-7) ────────────────────────────────────
  INSERT INTO public.tenant_billing_events (
    organization_id,
    event_type,
    changed_by_super_admin_id,
    reason,
    occurred_at_utc
  )
  VALUES (
    p_org_id,
    'DOMAINS_UPDATED',
    p_super_admin_user_id,
    p_reason,
    NOW()
  );
END;
$$;

REVOKE ALL ON FUNCTION public.super_admin_update_allowed_domains(
  UUID, text[], UUID, TEXT
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.super_admin_update_allowed_domains(
  UUID, text[], UUID, TEXT
) TO authenticated;
