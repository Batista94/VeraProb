-- =============================================================================
-- Migration: 20260909000003 — O(1) JWT permission helpers (Pilar 1.3)
--
-- STABLE SQL functions reading only auth.jwt() — no table access.
-- Placed in public schema (Supabase blocks CREATE in auth schema).
-- RLS policies invoke public.has_permission(...) — O(1), no JOIN.
-- Invariants: INV-2 (no auth.uid()), INV-7.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.has_permission(perm text)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = public, auth
AS $$
  SELECT COALESCE(
    (auth.jwt() -> 'app_metadata' -> 'permissions') ? '*'
    OR (auth.jwt() -> 'app_metadata' -> 'permissions') ? perm,
    false
  );
$$;

CREATE OR REPLACE FUNCTION public.has_permission_on(perm text, resource_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = public, auth
AS $$
  SELECT public.has_permission(perm)
     AND (
       (auth.jwt() -> 'app_metadata' -> 'perm_scopes' -> perm) IS NULL
       OR (auth.jwt() -> 'app_metadata' -> 'perm_scopes' -> perm) ? resource_id::text
     );
$$;

REVOKE ALL ON FUNCTION public.has_permission(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.has_permission_on(text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.has_permission(text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.has_permission_on(text, uuid) TO authenticated, service_role;
