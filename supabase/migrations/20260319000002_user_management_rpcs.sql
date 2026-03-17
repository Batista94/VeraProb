-- update_member_role: TENANT_ADMIN muda role de outro membro da mesma org
CREATE OR REPLACE FUNCTION public.update_member_role(
  p_target_user_id UUID,
  p_new_role        TEXT
)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  caller_org_id UUID;
  caller_role   TEXT;
BEGIN
  caller_org_id := (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid;
  caller_role   := auth.jwt() -> 'app_metadata' ->> 'role';

  IF caller_org_id IS NULL OR caller_role != 'TENANT_ADMIN' THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF p_new_role NOT IN ('TENANT_ADMIN', 'OPERATOR', 'AUDITOR') THEN
    RAISE EXCEPTION 'Invalid role: %', p_new_role;
  END IF;

  UPDATE public.user_roles
  SET role = p_new_role
  WHERE user_id = p_target_user_id
    AND organization_id = caller_org_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Member not found in organization';
  END IF;
END;
$$;

-- remove_member: TENANT_ADMIN remove membro da org; protege o último admin
CREATE OR REPLACE FUNCTION public.remove_member(
  p_target_user_id UUID
)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  caller_org_id  UUID;
  caller_role    TEXT;
  admin_count    INTEGER;
BEGIN
  caller_org_id := (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid;
  caller_role   := auth.jwt() -> 'app_metadata' ->> 'role';

  IF caller_org_id IS NULL OR caller_role != 'TENANT_ADMIN' THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  -- Last-admin invariant
  SELECT COUNT(*) INTO admin_count
  FROM public.user_roles
  WHERE organization_id = caller_org_id
    AND role = 'TENANT_ADMIN'
    AND user_id != p_target_user_id;

  IF admin_count = 0 THEN
    RAISE EXCEPTION 'Cannot remove the last administrator of the organization';
  END IF;

  DELETE FROM public.user_roles
  WHERE user_id = p_target_user_id
    AND organization_id = caller_org_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Member not found in organization';
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_member_role(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.remove_member(UUID) TO authenticated;
