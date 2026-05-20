# Forensic Test Plan: Fix Banned Until Infinity Regression

- **Migration ID**: 20260707000000
- **Purpose**: Verify that the `super_admin_archive_organization` RPC does not set `banned_until = 'infinity'` in the `auth.users` table, which causes HTTP 500 crashes in GoTrue (Supabase Auth). Re-apply the finite sentinel value '9999-12-31 23:59:59+00'::timestamptz.
- **Related Issues**: Regression introduced by migration `20260706000005_fix_archive_impersonation_column.sql`.

## Verification Details

### Automated Tests
- Running pgTAP regression test suite to verify constraints.
- Test command:
  ```bash
  supabase db test
  ```
  Specifically `supabase/tests/banned_until_infinity_regression_test.sql` must pass Test 1 and Test 2.

### Manual Verification
- Execute function directly via sql editor if needed.
