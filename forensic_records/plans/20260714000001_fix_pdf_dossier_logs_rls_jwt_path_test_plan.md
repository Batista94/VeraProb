# Test Plan: 20260714000001_fix_pdf_dossier_logs_rls_jwt_path

## Migration Summary

Corrective migration replacing the RLS policy on `pdf_dossier_logs` to use the
canonical JWT claim path `auth.jwt() -> 'app_metadata' ->> 'org_id'` instead of
the incorrect `auth.jwt() ->> 'organization_id'`.

## INV Compliance

| INV | Status | Detail |
|-----|--------|--------|
| INV-2 | ✅ Fixed | `auth.jwt() -> 'app_metadata' ->> 'org_id'` — matches custom_access_token_hook |
| INV-22 | ✅ | Tenant isolation preserved via org_id filter |
| INV-DB | ✅ | DROP POLICY IF EXISTS + CREATE — zero-downtime |

## Test Cases (pgTap)

### TC-1: Policy exists with correct name
- **Assert**: `policies_are('public', 'pdf_dossier_logs', ARRAY['PDF dossier logs tenant isolation'])`

### TC-2: RLS is enabled
- **Assert**: `has_table('public', 'pdf_dossier_logs')` + `row_security_active('public', 'pdf_dossier_logs')`

### TC-3: Tenant isolation — Org-A cannot see Org-B rows
- Insert row with `organization_id = org_a_uuid`
- Set JWT claims to `org_b_uuid`
- SELECT must return 0 rows

### TC-4: Tenant sees own data
- Insert row with `organization_id = org_a_uuid`
- Set JWT claims to `org_a_uuid`
- SELECT must return 1 row

## Predecessor
- Replaces broken policy from `20260713000001_fix_pdf_dossier_logs_rls.sql`
