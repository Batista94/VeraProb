-- ============================================================
-- PactaFlow — Phase 6: Organization Management RPCs
-- ============================================================
-- REASON:
--   Allow admins to list and manage members of their organization.
--   Requires SECURITY DEFINER to access auth.users schema safely.
-- ============================================================

-- RPC: get_org_members
-- Lists all users belonging to the current organization (from JWT).
CREATE OR REPLACE FUNCTION public.get_org_members()
RETURNS TABLE (
  user_id       UUID,
  email         TEXT,
  role          TEXT,
  invited_at    TIMESTAMPTZ,
  last_sign_in  TIMESTAMPTZ
) 
LANGUAGE plpgsql
SECURITY DEFINER -- Required to access auth.users
SET search_path = public, auth
AS $$
  DECLARE
    caller_org_id UUID;
  BEGIN
    -- 1. Get organization ID from the authenticated user's JWT
    caller_org_id := (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid;

    IF caller_org_id IS NULL THEN
      RAISE EXCEPTION 'Unauthorized: User does not belong to an organization';
    END IF;

    -- 2. Return membership data joined with auth.users
    RETURN QUERY
    SELECT 
      u.id,
      u.email::text,
      ur.role::text,
      u.created_at as invited_at,
      u.last_sign_in_at as last_sign_in
    FROM auth.users u
    JOIN public.user_roles ur ON ur.user_id = u.id
    WHERE ur.organization_id = caller_org_id
    ORDER BY u.created_at DESC;
  END;
$$;

-- Grant access to authenticated users
GRANT EXECUTE ON FUNCTION public.get_org_members() TO authenticated;
