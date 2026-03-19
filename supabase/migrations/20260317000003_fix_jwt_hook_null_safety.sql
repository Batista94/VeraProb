-- ============================================================
-- veraprob — Phase 6: JWT Hook NULL Safety Fix (Bloco 1.6)
-- ============================================================
-- REASON:
--   The previous implementation used the string 'null' for
--   app_metadata.org_id. While safe (Postgres fails to cast
--   'null' to UUID), it generates noise in logs.
--   This fix uses proper SQL NULL.
-- ============================================================

CREATE OR REPLACE FUNCTION public.custom_access_token_hook(event jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
  DECLARE
    claims jsonb;
    user_role record;
  BEGIN
    -- Fetch the user's role and organization
    SELECT organization_id, role INTO user_role 
    FROM public.user_roles 
    WHERE user_id = (event->>'user_id')::uuid;

    claims := event->'claims';

    IF FOUND THEN
      -- Inject the required isolation context into the JWT
      claims := jsonb_set(claims, '{app_metadata, org_id}', to_jsonb(user_role.organization_id));
      claims := jsonb_set(claims, '{app_metadata, role}', to_jsonb(user_role.role));
    ELSE
      -- Use proper NULLs for missing context
      claims := jsonb_set(claims, '{app_metadata, org_id}', 'null'::jsonb);
      claims := jsonb_set(claims, '{app_metadata, role}', 'null'::jsonb);
    END IF;

    -- Update the event
    event := jsonb_set(event, '{claims}', claims);
    RETURN event;
  END;
$$;
