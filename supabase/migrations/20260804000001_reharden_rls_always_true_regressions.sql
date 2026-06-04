-- =============================================================================
-- Migration: Re-harden RLS — close always-true policy regressions + spatial_ref_sys
-- =============================================================================
--
-- HOSTILE REVIEW (Mandatory Step 0 — QA/Security Lead):
--
-- Three security regressions were introduced AFTER migration 20260602000001
-- hardened these surfaces. Because migrations are append-only, the hardening
-- intent was silently undone by later feature migrations. This migration is the
-- forward re-hardening; it runs last in `supabase db reset`, so the final DB
-- state is correct. A standing pgTAP invariant test (inv22_always_true_policy_
-- invariant_test.sql) plus a scanner rule (ALWAYS-TRUE-RLS-POLICY) are added so
-- this regression class can never reach main again.
--
-- Regression A — spatial_ref_sys readable by client roles (INV-2, lint only):
--   NOT FIXABLE FROM A MIGRATION on Supabase, and NOT a tenant-data leak.
--   spatial_ref_sys is owned by `supabase_admin` and its grants (incl.
--   `SELECT TO PUBLIC` from PostGIS install) were made by `supabase_admin`.
--   Migrations run as `postgres`, which is neither superuser nor a member of
--   `supabase_admin`, so it cannot revoke another grantor's privileges — every
--   `REVOKE ... FROM PUBLIC/anon/authenticated` is a silent no-op (Postgres emits
--   `WARNING 01006: no privileges could be revoked`). The original 20260602000001
--   REVOKE was therefore always ineffective. We do NOT ship another no-op here.
--   Risk assessment: spatial_ref_sys holds only public geodesy reference data
--   (srid, auth_name, auth_srid, srtext, proj4text) — NO organization_id, NO
--   tenant rows, NO PII. INV-22 is not violated. The residual concern is pure
--   SRID/schema enumeration of public reference data. The only effective
--   mitigation (move PostGIS to a dedicated schema, or exclude the table from the
--   PostgREST exposed schema) is a platform/config operation requiring
--   supabase_admin and is tracked separately, not in this migration.
--   See test plan 20260804000001 §A for the full reasoning and the standing
--   inv22_always_true_policy_invariant_test.sql for the "no tenant column" guard.
--
-- Regression B — telegram_pending_links cross-tenant R/W via anon (INV-1/22/26):
--   20260614000001_telegram_self_link.sql re-created `tpl_service_all` as
--   PERMISSIVE FOR ALL USING(true) WITH CHECK(true) with no role clause (=> PUBLIC).
--   20260527170000 granted SELECT/INSERT/UPDATE on the table to `anon`. The
--   RESTRICTIVE deny-all from 20260602000001 covers only `authenticated`, so an
--   UNAUTHENTICATED PostgREST caller (anon) satisfied (permissive=true) with no
--   restrictive blocker — full cross-tenant read/write of pending self-link
--   tokens (short_id enumeration → resolve_telegram_orphan_with_link hijack).
--   authenticated was already correctly blocked (restrictive deny-all wins).
--   Closure: DROP tpl_service_all (service_role bypasses RLS — webhook + the
--   SECURITY DEFINER RPCs are unaffected), REVOKE anon grants, add a RESTRICTIVE
--   deny-all for anon mirroring the authenticated one.
--
-- Regression C — telegram_status_queries always-true INSERT (INV-1/3/22, latent):
--   20260616000001_evidence_compliance_status.sql re-created `tsq_insert_service`
--   as PERMISSIVE FOR INSERT WITH CHECK(true) with no role clause (=> PUBLIC).
--   Currently latent: neither anon nor authenticated holds the INSERT table grant,
--   so it is not exploitable today — but it is a lint violation and a landmine the
--   moment any future migration grants INSERT. Defense-in-depth fix.
--   Closure: re-scope tsq_insert_service to service_role only, add a RESTRICTIVE
--   deny-all INSERT for authenticated, revoke residual anon grants.
--
-- INVARIANTS ENFORCED: INV-1, INV-2, INV-3, INV-22, INV-26.
-- =============================================================================

SET client_min_messages TO 'WARNING';

-- ── A. spatial_ref_sys — see header. No executable statement: the REVOKE is not
--       authorizable by the `postgres` migration role and would be a no-op. The
--       table carries no tenant data; the invariant test asserts that fact.

-- ── B. telegram_pending_links — drop permissive policy, close anon ────────────
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'telegram_pending_links'
  ) THEN
    EXECUTE 'DROP POLICY IF EXISTS tpl_service_all ON public.telegram_pending_links';
    EXECUTE 'REVOKE ALL ON TABLE public.telegram_pending_links FROM anon';
    EXECUTE 'DROP POLICY IF EXISTS "deny-all anon: telegram_pending_links" ON public.telegram_pending_links';
    EXECUTE $q$
      CREATE POLICY "deny-all anon: telegram_pending_links"
        ON public.telegram_pending_links
        AS RESTRICTIVE
        FOR ALL
        TO anon
        USING (false)
        WITH CHECK (false)
    $q$;
  END IF;
END;
$$;

-- ── C. telegram_status_queries — scope INSERT to service_role, deny others ────
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'telegram_status_queries'
  ) THEN
    EXECUTE 'DROP POLICY IF EXISTS tsq_insert_service ON public.telegram_status_queries';
    EXECUTE $q$
      CREATE POLICY tsq_insert_service
        ON public.telegram_status_queries
        FOR INSERT
        TO service_role
        WITH CHECK (true)
    $q$;
    EXECUTE 'DROP POLICY IF EXISTS "deny-all insert: telegram_status_queries" ON public.telegram_status_queries';
    EXECUTE $q$
      CREATE POLICY "deny-all insert: telegram_status_queries"
        ON public.telegram_status_queries
        AS RESTRICTIVE
        FOR INSERT
        TO authenticated
        WITH CHECK (false)
    $q$;
    EXECUTE 'REVOKE ALL ON TABLE public.telegram_status_queries FROM anon';
  END IF;
END;
$$;
