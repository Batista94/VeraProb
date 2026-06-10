-- =============================================================================
-- Migration: Harden the identity / tenant trust-root tables
--            (revoke client-role DML on user_roles + organizations).
--
-- FORENSIC FINDING (CIA sweep — JWT claim trust-root audit, 2026-06-09):
-- Tenant isolation (RLS) trusts the `organization_id` claim. That claim is
-- injected at token issuance by `public.custom_access_token_hook` (SECURITY
-- DEFINER), which derives it from the `user_roles` table. Therefore the integrity
-- of the entire RLS isolation model reduces to the integrity of `user_roles`:
-- if a client could write its own `user_roles` row, it would self-assign any
-- organization_id and the hook would mint a token carrying the victim's tenant.
--
-- CURRENT STATE: `user_roles` (and `organizations`) have RLS enabled with ONLY a
-- SELECT policy — so direct INSERT/UPDATE/DELETE by `authenticated` is already
-- denied by RLS (no permissive write policy). HOWEVER, `authenticated` still holds
-- the table-level GRANT INSERT/UPDATE/DELETE (legacy ALTER DEFAULT PRIVILEGES).
-- That dead grant is a latent escalation primitive: a single future permissive
-- write policy (added by mistake) would immediately become exploitable. Defense
-- in depth requires removing the grant so the trust root cannot be written by a
-- client role under ANY future policy.
--
-- SAFETY: every legitimate writer of these tables is SECURITY DEFINER, owner
-- `postgres`, and runs with its own authorization checks — verified:
--   user_roles  : accept_invitation, deactivate_member, reactivate_member,
--                 update_member_role, super_admin_toggle_member_status,
--                 super_admin_archive/unarchive_organization, ...
--   organizations: super_admin_create_organization, super_admin_archive/unarchive,
--                 super_admin_update_allowed_domains/quota, accept_invitation, ...
-- These run as the definer (postgres) and DO NOT depend on the `authenticated`
-- grant, so revoking it breaks no flow. `service_role` is untouched.
-- `super_admin_users` is already sound (no client grant + deny-all authenticated
-- USING(false) policy) — no change needed.
--
-- `authenticated` retains SELECT (org-scoped policy) on both tables.
-- `anon` already holds no grant on either table.
--
-- Idempotent: REVOKE of an absent privilege is a no-op. Safe to re-run.
-- INV-DB: REVOKE statements are privilege metadata, not destructive DML. The
-- DELETE keyword below is a PRIVILEGE name, annotated per Regression-Ack discipline.
--
-- Invariants: INV-1 (org claim integrity), INV-2 (RLS claim-source integrity),
-- INV-22 (tenant isolation), INV-DATA-API-GRANT (CI block #13).
-- =============================================================================

SET client_min_messages TO 'WARNING';

-- ── user_roles: the direct source of the organization_id claim ───────────────
REVOKE INSERT, UPDATE, DELETE ON public.user_roles FROM authenticated; -- INV-DB: zero-downtime-verified (privilege REVOKE, not DML)

-- ── organizations: tenant root record (same latent dead-grant pattern) ───────
REVOKE INSERT, UPDATE, DELETE ON public.organizations FROM authenticated; -- INV-DB: zero-downtime-verified (privilege REVOKE, not DML)
