-- =============================================================================
-- Migration: list_portal_submissions RPC — Sprint A (Auditor review) M6
-- Purpose:   Safe read path over the deny-all `portal_evidence_submissions`
--            quarantine table for the auditor PENDING_AUDIT review panel. The
--            table itself never grants client SELECT (paths/declared metadata
--            must not leak); this SECURITY DEFINER RPC projects only the columns
--            an auditor needs, scoped to the caller's org (INV-22).
--
--            Pairs with audit_portal_submission (M5): list → accept/reject.
--
-- Council: Architect ✅ · Senior ✅ · QA-Security ✅ · Business ✅ · Lead ✅
-- Invariants: INV-1, INV-2, INV-22, INV-26.
-- Depends on: 20260817000002 (submissions), 20260817000005 (dea.submission_id).
-- =============================================================================

SET client_min_messages TO 'WARNING';

CREATE OR REPLACE FUNCTION public.list_portal_submissions(
  p_organization_id UUID,
  p_queue_entry_id  UUID
)
RETURNS TABLE (
  submission_id          UUID,
  attachment_id          UUID,
  file_name              TEXT,
  mime_type_detected     TEXT,
  file_size_bytes_actual BIGINT,
  sha256_server          TEXT,
  status                 TEXT,
  submitted_at_utc       TIMESTAMPTZ,
  finalized_at_utc       TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_jwt_org  TEXT;
  v_jwt_role TEXT;
BEGIN
  -- Auth (INV-1, INV-26: failures → empty/▢42501, never an oracle).
  v_jwt_org := auth.jwt() -> 'app_metadata' ->> 'org_id';
  IF v_jwt_org IS NULL OR v_jwt_org::uuid <> p_organization_id THEN
    RAISE EXCEPTION 'Listing rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  v_jwt_role := auth.jwt() -> 'app_metadata' ->> 'role';
  IF v_jwt_role IS NULL OR v_jwt_role NOT IN ('TENANT_ADMIN', 'AUDITOR') THEN
    RAISE EXCEPTION 'Listing rejected.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  RETURN QUERY
    SELECT
      pes.id,
      dea.id,
      pes.file_name,
      pes.mime_type_detected,
      pes.file_size_bytes_actual,
      pes.sha256_server,
      pes.status,
      pes.submitted_at_utc,
      pes.finalized_at_utc
    FROM public.portal_evidence_submissions pes
    LEFT JOIN public.dispute_evidence_attachments dea
      ON dea.submission_id = pes.id AND dea.deleted_at IS NULL
   WHERE pes.organization_id = p_organization_id
     AND pes.queue_entry_id = p_queue_entry_id
     AND pes.deleted_at IS NULL
     AND pes.status = 'PENDING_AUDIT'
   ORDER BY pes.submitted_at_utc;
END;
$$;

REVOKE ALL ON FUNCTION public.list_portal_submissions(UUID, UUID)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.list_portal_submissions(UUID, UUID)
  TO authenticated;

RESET client_min_messages;
