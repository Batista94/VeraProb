-- ============================================================
-- veraprob — Fix Invitations Anon Grant
-- ============================================================
-- REASON:
--   AcceptInviteScreen.findActiveByToken() returns 0 rows for anon
--   because the invitations table never received GRANT SELECT for anon
--   and authenticated.
--   The RLS policy "Public token validation" already restricts SELECT
--   to the safe subset (pending, non-revoked, non-expired).
-- ============================================================

GRANT SELECT ON public.invitations TO anon;
GRANT SELECT ON public.invitations TO authenticated;
