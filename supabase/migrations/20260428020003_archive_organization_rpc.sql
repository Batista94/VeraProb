-- RPC: super_admin_archive_organization
-- Atomically sets status=ARCHIVED, revokes API secrets, appends audit record.
-- INV-3: Secrets revoked via revoked_at — never deleted.
-- INV-26: 404 parity — same error for not-found AND wrong-org.
-- INV-10: Already-archived returns distinct error code P0003.

CREATE OR REPLACE FUNCTION public.super_admin_archive_organization(
  p_org_id         UUID,
  p_reason         TEXT,
  p_super_admin_id UUID
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- INV-26: 404-parity — treat DELETED as non-existent
  IF NOT EXISTS (
    SELECT 1 FROM organizations
    WHERE id = p_org_id AND status <> 'DELETED'
  ) THEN
    RAISE EXCEPTION 'Not found' USING ERRCODE = 'P0002';
  END IF;

  -- Idempotency guard: already archived is a distinct error (P0003)
  IF EXISTS (
    SELECT 1 FROM organizations
    WHERE id = p_org_id AND status = 'ARCHIVED'
  ) THEN
    RAISE EXCEPTION 'Organization already archived' USING ERRCODE = 'P0003';
  END IF;

  -- Set status to ARCHIVED
  UPDATE organizations
  SET    status     = 'ARCHIVED',
         updated_at = NOW()
  WHERE  id = p_org_id;

  -- Revoke all active API secrets (INV-3: set revoked_at, never DELETE)
  UPDATE org_api_secrets
  SET    revoked_at = NOW(),
         rotated_at = NOW()
  WHERE  organization_id = p_org_id
    AND  revoked_at IS NULL;

  -- Append-only audit record (INV-3)
  INSERT INTO system_audit_log
    (event_type, severity, organization_id, reason, actor_type, source, payload)
  VALUES
    (
      'ORG_ARCHIVED',
      'warning',
      p_org_id,
      p_reason,
      'HUMAN',
      'rpc',
      jsonb_build_object(
        'super_admin_id', p_super_admin_id,
        'reason',         p_reason
      )
    );
END;
$$;
