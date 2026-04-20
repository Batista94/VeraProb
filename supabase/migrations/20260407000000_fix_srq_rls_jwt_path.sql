-- ============================================================
-- Fix sanction_review_queue RLS policies — JWT path alignment
-- ============================================================
-- srq_select_own_org and srq_update_own_org were using
-- (auth.jwt() ->> 'organization_id') which never matches any
-- valid JWT in this system. All other RLS policies use the
-- canonical path: (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid
-- (set by the custom_access_token_hook in auth.users).
--
-- srq_insert_service (WITH CHECK (true)) is untouched — it is
-- intentionally permissive for SECURITY DEFINER trigger writes.
-- ============================================================

DROP POLICY IF EXISTS srq_select_own_org ON public.sanction_review_queue;
DROP POLICY IF EXISTS srq_update_own_org ON public.sanction_review_queue;

CREATE POLICY srq_select_own_org ON public.sanction_review_queue
  FOR SELECT
  USING (
    organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid
    AND (auth.jwt() -> 'app_metadata' ->> 'role') IN ('AUDITOR', 'ADMIN', 'SUPER_ADMIN')
  );

CREATE POLICY srq_update_own_org ON public.sanction_review_queue
  FOR UPDATE
  USING (
    organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid
    AND (auth.jwt() -> 'app_metadata' ->> 'role') IN ('AUDITOR', 'ADMIN')
  )
  WITH CHECK (
    organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid
  );
