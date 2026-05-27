# Test Plan: 20260717000008_grant_tenant_access_tables

## Objective
Verify that Tenant-Access tables have the exact required grants (SELECT, INSERT, UPDATE, DELETE to `authenticated` and ALL to `service_role`), and NO grants to `anon` or `public`.

## Tables to verify:
* public.organizations
* public.user_roles
* public.drivers
* public.invitations
* public.provider_api_keys
* public.csv_mapping_templates
* public.sla_templates
* public.sla_audit_ledger

## Test Steps
1. Execute pgTAP tests to check table privileges for `authenticated`, `anon`, and `service_role`.
2. Confirm `authenticated` has SELECT, INSERT, UPDATE, DELETE.
3. Confirm `service_role` has SELECT, INSERT, UPDATE, DELETE.
4. Confirm `anon` has NO privileges (not SELECT, not INSERT, not UPDATE, not DELETE).
