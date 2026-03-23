-- =============================================================================
-- Phase 9.3 — Hotfix: Fix Role in Sanction Queue RLS
-- =============================================================================
-- The previous RLS policy checked if role was 'admin', but user_roles
-- enforces the exact string 'TENANT_ADMIN'. This caused the stream to return
-- empty on the frontend, breaking the real-time badge.
-- =============================================================================

DROP POLICY IF EXISTS srq_select_own_org ON public.sanction_review_queue;
CREATE POLICY srq_select_own_org
  ON public.sanction_review_queue
  FOR SELECT
  USING (
    organization_id::text = (auth.jwt() ->> 'organization_id')
    AND (auth.jwt() ->> 'role') IN ('TENANT_ADMIN', 'AUDITOR')
  );

DROP POLICY IF EXISTS srq_update_own_org ON public.sanction_review_queue;
CREATE POLICY srq_update_own_org
  ON public.sanction_review_queue
  FOR UPDATE
  USING (
    organization_id::text = (auth.jwt() ->> 'organization_id')
    AND (auth.jwt() ->> 'role') IN ('TENANT_ADMIN', 'AUDITOR')
  );
