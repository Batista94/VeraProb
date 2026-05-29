BEGIN;
SELECT plan(3);

-- Verify function exists
SELECT has_function('public', 'super_admin_update_organization_quota', 'Function super_admin_update_organization_quota exists');

-- Verify function is defined with exactly 16 arguments
SELECT results_eq(
  $$
    SELECT count(*)::int
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname = 'super_admin_update_organization_quota'
  $$,
  ARRAY[1],
  'Function super_admin_update_organization_quota has exactly 1 overload'
);

-- Verify the parameter types of the unique overload match the expected 16-parameter list
SELECT results_eq(
  $$
    SELECT pg_get_function_identity_arguments(p.oid)
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname = 'super_admin_update_organization_quota'
  $$,
  ARRAY['p_org_id uuid, p_new_plan_type text, p_new_max_vehicles integer, p_new_max_contracts integer, p_super_admin_user_id uuid, p_reason text, p_capabilities jsonb, p_tool_cost_cents bigint, p_dwell_time_seconds integer, p_billing_day smallint, p_contact_email text, p_external_id text, p_organization_type text, p_trade_name text, p_legal_name text, p_expected_updated_at timestamp with time zone'],
  'Function parameters match the expected 16-parameter signature'
);

SELECT * FROM finish();
ROLLBACK;
