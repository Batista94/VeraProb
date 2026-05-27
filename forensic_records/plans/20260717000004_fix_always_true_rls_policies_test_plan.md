# Test Plan — 20260717000004_fix_always_true_rls_policies

**Migration:** `supabase/migrations/20260717000004_fix_always_true_rls_policies.sql`
**Linter ID:** 0014 — `rls_policy_always_true`
**Risk:** High — INSERT behavior change for authenticated users. Requires verification of Dart write paths.

---

## Problem

Two policies use `WITH CHECK (true)` for `authenticated`, allowing any authenticated user to INSERT rows with ANY `organization_id` — a cross-tenant write vector.

### Policy 1: `sla_audit_ledger` "Ledger Insert"

```sql
-- Current (UNSAFE)
FOR INSERT TO authenticated WITH CHECK (true);
```

Any authenticated user can insert SLA audit records into another tenant's partitions. The partition-level policies restrict SELECTs to the user's own org, but the parent-level INSERT policy bypasses this for writes routed through the parent.

**Context:** Dart code uses `sla_audit_ledger_v2` (not the partitioned parent). The partitioned `sla_audit_ledger` is written only by SECURITY DEFINER RPCs. The fix (`WITH CHECK (organization_id = jwt_org_id)`) is belt-and-suspenders — it closes the gap without affecting any current client writes.

### Policy 2: `system_audit_log` "system_audit_log_insert_policy"

```sql
-- Current (UNSAFE)
FOR INSERT TO authenticated WITH CHECK (true);
```

Dart client inserts directly via `postgres_system_audit_log_service.dart`. Super admins write audit events targeting a SPECIFIC org (not their own JWT org_id, which is NULL for super admins). The fix allows super admins unconditionally + restricts regular users to their own org.

---

## JWT Claim Reference (INV-2)

All policies use `auth.jwt() -> 'app_metadata' ->> 'org_id'` (app_metadata nest).
- Regular authenticated users: `app_metadata.org_id` = their organization UUID
- Super admins: `app_metadata.super_admin = 'true'`, `app_metadata.org_id` may be NULL
- Anon: no `sub` claim, no `app_metadata.org_id`

---

## Pre-migration Assertions

```sql
-- Both policies must exist with always-true WITH CHECK before migration
SELECT tablename, policyname, with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('sla_audit_ledger', 'system_audit_log')
  AND cmd = 'INSERT'
  AND with_check = 'true'
ORDER BY tablename;
-- Expected: 2 rows
```

---

## Post-migration Assertions

```sql
-- 1. No INSERT policy with literal `true` WITH CHECK
SELECT tablename, policyname, with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('sla_audit_ledger', 'system_audit_log')
  AND cmd = 'INSERT'
  AND with_check = 'true'
ORDER BY tablename;
-- Expected: 0 rows

-- 2. sla_audit_ledger INSERT policy uses contracts JOIN (no direct org_id column)
SELECT with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'sla_audit_ledger'
  AND policyname = 'Ledger Insert';
-- Expected: contains 'contracts' and 'app_metadata' (EXISTS subquery via contract_id)

-- 3. system_audit_log INSERT policy uses super_admin exception + org_id check
SELECT with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'system_audit_log'
  AND policyname = 'system_audit_log_insert_policy';
-- Expected: contains 'super_admin' and 'organization_id'
```

---

## Application Impact Verification

### Dart path: `postgres_system_audit_log_service.dart`

Regular authenticated user writes:
```dart
await _client.from('system_audit_log').insert({
  'organization_id': organizationId,  // must equal JWT app_metadata.org_id
  ...
});
```
→ Must succeed post-migration (org_id matches JWT).

Super admin writes:
```dart
await _client.from('system_audit_log').insert({
  'organization_id': targetOrganizationId,  // a different org's UUID
  ...
});
```
→ Must succeed post-migration (super_admin = 'true' check passes).

### E2E verification

```powershell
make test-e2e
```

Key flows:
1. **Admin creates org** → super admin audit log write (must succeed)
2. **Member performs action** → regular user audit log write (must succeed)
3. **Cross-tenant write attempt** (if E2E adversarial test exists) → must be BLOCKED

### pgTAP verification

```powershell
make test-db
```

If no existing pgTAP test covers this, add a test in `supabase/tests/` verifying:
- Regular user INSERT with own org_id → allowed
- Regular user INSERT with foreign org_id → blocked (`new row violates row-level security policy`)
- Super admin INSERT with any org_id → allowed

---

## Rollback

```sql
-- Revert to always-true if super admin audit logging breaks:
DROP POLICY IF EXISTS "system_audit_log_insert_policy" ON public.system_audit_log;
CREATE POLICY "system_audit_log_insert_policy"
  ON public.system_audit_log
  FOR INSERT TO authenticated
  WITH CHECK (true);
-- Re-investigate super admin JWT claim before re-applying fix.
```
