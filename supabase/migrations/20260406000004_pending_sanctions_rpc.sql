-- =============================================================================
-- Migration: get_pending_sanctions_count RPC
--
-- Returns the count of pending sanctions for the given organization.
-- SECURITY DEFINER to allow efficient count without full table scan via RLS.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_pending_sanctions_count(
  p_org_id UUID
)
RETURNS INT
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT COUNT(*)::INT
  FROM public.sanction_review_queue
  WHERE organization_id = p_org_id
    AND status = 'pending';
$$;

-- Grant execution to authenticated users
REVOKE ALL ON FUNCTION public.get_pending_sanctions_count(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_pending_sanctions_count(UUID)
  TO authenticated;
