# Test Plan: RBAC Assign/Revoke Hardening (20260916000001)

## Context
This migration hardens the tenant role assignment and revocation process by enforcing strict hierarchy guards inside `assign_tenant_role` and `revoke_tenant_role`. It ensures users cannot manage roles of targets possessing permissions they lack, and cannot grant or revoke roles containing permissions they don't possess. It also adds automatic syncing for the coarse `TENANT_ADMIN` role when the `Administrador` tenant role is granted or revoked, including a last-admin guard to prevent removing the final administrator from an organization.

## Scope
- `assign_tenant_role` and `revoke_tenant_role` RPCs.
- `approve_role_change` RPC.
- Helper functions: `_rbac_assert_can_grant_role`, `_rbac_assert_can_manage_target`, `_rbac_sync_coarse_role_admin`.

## Pre-conditions
- Users exist across two tenant organizations (to verify isolation).
- Base tenant roles (`Administrador`, `Validador`, `Operador`) exist.
- Test uses pgTAP for assertion validation inside an active transaction.

## Test Cases

### 1. Guard: `_rbac_assert_can_grant_role`
- **Setup**: Impersonate a user with `Validador` role (lacks some permissions of `Administrador`).
- **Action**: Attempt to `assign_tenant_role` the `Administrador` role to another user.
- **Expected**: `throws_ok` with `insufficient_privilege`.

- **Action**: Attempt to `assign_tenant_role` the `Operador` role to another user.
- **Expected**: `lives_ok` (assuming `Validador` has all permissions of `Operador`).

### 2. Guard: `_rbac_assert_can_manage_target`
- **Setup**: Impersonate a user with `Validador` role.
- **Action**: Attempt to `revoke_tenant_role` the `Administrador` role from an existing admin.
- **Expected**: `throws_ok` with `insufficient_privilege` (because the target holds permissions the caller lacks).

### 3. Coarse Role Sync: Admin Granted via Four-Eyes
- **Setup**: Impersonate an `Administrador` (`*`). Target user holds `Operador` coarse role.
- **Action**: `assign_tenant_role` `Administrador` to target.
- **Expected**: Request created (`PENDING`). Coarse role unchanged.
- **Action**: Impersonate a second `Administrador`. `approve_role_change`.
- **Expected**: Target `user_roles.role` becomes `TENANT_ADMIN`.

### 4. Coarse Role Sync: Admin Revoked
- **Setup**: Impersonate an `Administrador` (`*`). Target user holds `TENANT_ADMIN` and `Administrador`. Another admin exists.
- **Action**: `revoke_tenant_role` `Administrador` from target.
- **Expected**: Target `user_roles.role` becomes `OPERATOR`.

### 5. Coarse Role Sync: Last-Admin Guard
- **Setup**: Impersonate an `Administrador`. Target is the *only* active admin in the organization.
- **Action**: `revoke_tenant_role` `Administrador` from target.
- **Expected**: `throws_ok` with `Cannot demote the last administrator`.

## Post-conditions
- All mutations rollback automatically at the end of the pgTAP transaction. No side effects.
