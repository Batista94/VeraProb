# Forensic Test Plan: Deactivate Member Login Block

## Target
`supabase/migrations/20260918000003_deactivate_member_login_block.sql`

## Overview
This plan verifies the fix for Bug 1, where deactivated members could still log in because the `deactivate_member` RPC only toggled `user_roles.is_active = false` without actually blocking GoTrue auth. The fix introduces a real ban via `banned_until = 'infinity'` and also hardens the JWT hook.

## Scenarios Covered

1. **Deactivate Member**
   - **Condition:** Admin calls `deactivate_member` on an active user.
   - **Expected Result:** `user_roles.is_active` becomes `false`. `auth.users.banned_until` becomes `'infinity'`.

2. **Defense in Depth (JWT Hook)**
   - **Condition:** A deactivated user (somehow bypassing GoTrue or using an old token refresh) invokes the `custom_access_token_hook`.
   - **Expected Result:** The hook returns `org_id=null` and `permissions=[]` because it checks `ur.is_active = true`.

3. **Reactivate Member**
   - **Condition:** Admin calls `reactivate_member` on a deactivated user.
   - **Expected Result:** `auth.users.banned_until` is cleared (NULL) and `user_roles.is_active` becomes `true`.

## Invariants Guarded
- **INV-1 & INV-22:** Tenant isolation and confidentiality (inactive users cannot see tenant data).
- **INV-3:** Audit trail (MEMBER_DEACTIVATED and MEMBER_REACTIVATED events are logged, though tested implicitly via lives_ok here as the audit functions were not changed in behavior, just reused).
