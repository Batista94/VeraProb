-- =============================================================================
-- Migration: list_portal_submissions_with_justification
--
-- The auditor review panel could see a portal counter-evidence file but NOT the
-- carrier's written justification: list_portal_submissions (20260817000006)
-- never projected portal_evidence_submissions.justification_text, so the
-- testimony that ships WITH a file submission was invisible. (The text-only
-- contest path already had list_portal_justification_submissions.)
--
-- Adding a column to a RETURNS TABLE requires DROP + CREATE (CREATE OR REPLACE
-- cannot change the return shape). The argument signature is UNCHANGED
-- (uuid, uuid), so PostgREST resolution and committed callers are unaffected;
-- the matching pgTAP (20260817000006_*) is hardened in the same package to assert
-- the new column. Grant re-asserted (INV-DATA-API-GRANT).
--
-- Council: Architect ✅ · Senior ✅ · QA-Security ✅ · Lead ✅
-- Invariants: INV-1, INV-2, INV-22, INV-26, INV-DATA-API-GRANT.
-- =============================================================================
-- pr_scanner: ignore-regression
--   Council-approved: additive projection of an existing sealed column on a
--   read-only SECURITY DEFINER RPC; no merged migration edited.
SET client_min_messages TO 'WARNING';

DROP FUNCTION IF EXISTS public.list_portal_submissions(UUID, UUID);

CREATE FUNCTION public.list_portal_submissions(
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
  justification_text     TEXT,
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
      pes.justification_text,
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
