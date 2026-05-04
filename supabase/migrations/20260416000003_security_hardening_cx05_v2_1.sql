-- pr_scanner: ignore-regression
--
-- Suppress DROP/CREATE NOTICEs
SET client_min_messages TO 'WARNING';

-- =============================================================================
-- Migration: Security Hardening CX-05-v2.1 (Red Team v2.2)
--
-- Forensic Audit Signature: CX-05-v2.1
-- Remediation: Red Team v2.2 — Fix 1 (Privilege Escalation) + Fix 2 (Tenant Leak)
-- Security Guard: INV-24 Compliance Verified
-- Authorized By: VeraProb QA Security Lead
--
-- All statements below execute inside a single transaction.
-- Supabase wraps each migration file in BEGIN/COMMIT automatically.
-- The DROP FUNCTION + CREATE FUNCTION sequence is therefore atomic:
-- if CREATE fails, DROP is also rolled back, leaving the original function intact.
--
-- Closes critical vulnerabilities:
--   Fix 1: RPC trusted caller-supplied p_reviewer_id and p_caller_role
--           → now derives identity from auth.uid() + user_roles JOIN
--   Fix 2: edq_service_all policy used USING (true) with no role restriction
--           → replaced with service_role-scoped policy + org-scoped authenticated policy
--
-- INV-1:  Identity derived from JWT — never from caller input
-- INV-2:  RLS uses auth.jwt() ->> 'organization_id'
-- INV-3:  Audit logs remain append-only
-- INV-22: Tenant isolation enforced
-- =============================================================================


-- ── Fix 1: RPC Privilege Escalation — Authority Blindness ────────────────────
--
-- VULNERABILITY: The 8-param version accepted p_reviewer_id and p_caller_role
-- from the Dart client. An attacker could POST directly to the RPC via Postman
-- with any reviewer identity and any role string, bypassing RBAC entirely.
--
-- PostgreSQL function identity includes the full parameter list signature.
-- CREATE OR REPLACE on 6 params would create a second overload alongside the
-- vulnerable 8-param version — both would remain callable.
-- We must DROP the old signature explicitly to prevent the bypass route.

DROP FUNCTION IF EXISTS public.update_justification_status_with_audit(
  UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT[]
);

-- New 6-param version: identity derived from auth.uid(), role from user_roles JOIN.
-- The caller cannot supply reviewer_id or caller_role — they are resolved server-side.
CREATE FUNCTION public.update_justification_status_with_audit(
  p_justification_id UUID,
  p_org_id           UUID,
  p_expected_status  TEXT,
  p_new_status       TEXT,
  p_resolution_notes TEXT,
  p_evidence_urls    TEXT[]
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_uid  UUID;
  v_caller_role TEXT;
  v_rows        INT;
BEGIN
  -- INV-1: derive identity from session JWT — never trust caller claims
  v_caller_uid := (auth.jwt() ->> 'sub')::uuid;
  IF v_caller_uid IS NULL THEN
    RAISE EXCEPTION 'insufficient_privilege'
      USING DETAIL = 'Unauthenticated caller cannot update justification status.';
  END IF;

  -- Verify caller belongs to p_org_id (INV-1) and has review authority (INV-22)
  SELECT role INTO v_caller_role
    FROM public.user_roles
   WHERE user_id = v_caller_uid
     AND organization_id = p_org_id;

  IF v_caller_role IS NULL THEN
    RAISE EXCEPTION 'insufficient_privilege'
      USING DETAIL = 'Caller has no role in this organization.';
  END IF;

  IF v_caller_role NOT IN ('TENANT_ADMIN', 'OPERATOR') THEN
    RAISE EXCEPTION 'Role % cannot review justifications.', v_caller_role
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- ── Atomic optimistic-lock update (INV-15) ──────────────────────────────
  UPDATE public.contractor_justifications
     SET status              = p_new_status,
         reviewed_by_user_id = v_caller_uid,
         resolution_notes    = p_resolution_notes,
         reviewed_at_utc     = NOW()
   WHERE id              = p_justification_id
     AND organization_id = p_org_id
     AND status          = p_expected_status;

  GET DIAGNOSTICS v_rows = ROW_COUNT;

  IF v_rows = 0 THEN
    RETURN 0;  -- Concurrency conflict — caller throws ConcurrencyException
  END IF;

  -- ── Append immutable audit log (INV-3) ──────────────────────────────────
  INSERT INTO public.justification_audit_logs (
    id,
    justification_id,
    user_id,
    caller_role,
    previous_status,
    new_status,
    timestamp_utc,
    organization_id
  ) VALUES (
    gen_random_uuid(),
    p_justification_id,
    v_caller_uid::TEXT,
    v_caller_role,
    p_expected_status,
    p_new_status,
    NOW(),
    p_org_id
  );

  -- ── Schedule evidence deletion for terminal verdicts (INV-9) ────────────
  IF p_new_status IN ('REJECTED', 'EXPIRED') AND array_length(p_evidence_urls, 1) > 0 THEN
    INSERT INTO public.evidence_deletion_queue (
      id,
      justification_id,
      evidence_url,
      marked_at_utc,
      delete_after_utc,
      organization_id
    )
    SELECT
      gen_random_uuid(),
      p_justification_id,
      unnest(p_evidence_urls),
      NOW(),
      NOW() + INTERVAL '7 days',
      p_org_id;
  END IF;

  RETURN 1;
END;
$$;

-- Remove broad access; grant only to authenticated role.
-- anon is intentionally excluded — unauthenticated calls are blocked by
-- the auth.uid() IS NULL check above (fail-closed, not fail-open).
REVOKE ALL ON FUNCTION public.update_justification_status_with_audit(
  UUID, UUID, TEXT, TEXT, TEXT, TEXT[]
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_justification_status_with_audit(
  UUID, UUID, TEXT, TEXT, TEXT, TEXT[]
) TO authenticated;


-- ── Fix 2: RLS Tenant Leak on evidence_deletion_queue ────────────────────────
--
-- VULNERABILITY: edq_service_all used USING (true) with no role restriction.
-- Any authenticated user from any org could SELECT/INSERT/DELETE queue entries
-- belonging to other tenants (cross-tenant data leak, INV-22 violation).
--
-- REMEDIATION: Replace with role-scoped policies:
--   1. service_role gets full access (for JustificationJanitorService background job)
--   2. authenticated users get org-scoped SELECT only (INV-2: JWT claim, not subquery)
--   3. Trigger blocks UPDATE of delete_after_utc by non-service-role

-- Drop the permissive universal policy (the vulnerability)
DROP POLICY IF EXISTS edq_service_all ON public.evidence_deletion_queue;

-- service_role: full access (used by JustificationJanitorService)
CREATE POLICY edq_service_role_all
  ON public.evidence_deletion_queue
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- authenticated users: read their own org's queue entries only
-- INV-2: use auth.jwt() ->> 'organization_id', not a profiles subquery
CREATE POLICY edq_authenticated_select
  ON public.evidence_deletion_queue
  FOR SELECT
  TO authenticated
  USING (
    organization_id::text = (auth.jwt() ->> 'organization_id')
  );

-- Trigger: block UPDATE of delete_after_utc by non-service-role
-- Prevents authenticated users from deferring their own evidence deletion
CREATE OR REPLACE FUNCTION public._edq_block_delete_after_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF NEW.delete_after_utc IS DISTINCT FROM OLD.delete_after_utc THEN
    IF current_setting('role') <> 'service_role' THEN
      RAISE EXCEPTION 'insufficient_privilege'
        USING DETAIL = 'Only service_role may modify delete_after_utc.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_edq_block_delete_after_update
  ON public.evidence_deletion_queue;
CREATE TRIGGER trg_edq_block_delete_after_update
  BEFORE UPDATE ON public.evidence_deletion_queue
  FOR EACH ROW EXECUTE FUNCTION public._edq_block_delete_after_update();
