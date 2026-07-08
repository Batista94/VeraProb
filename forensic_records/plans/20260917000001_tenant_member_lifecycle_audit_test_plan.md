# Test Plan: Tenant Member-Lifecycle Governance Audit (20260917000001)

## Context

RBAC role assignment/revocation already logs to `system_audit_log` via `_rbac_audit()`, but that table was readable only by Super Admin (through the `service_role`-backed `super-admin-proxy` Edge Function). Member-lifecycle mutations (invite, accept invitation, revoke invitation, deactivate, reactivate, remove, legacy role change) logged nothing at all, and there was no tenant-facing surface to review governance history. This migration closes both gaps under the CIA triad:

- **Confidentiality:** new `get_tenant_governance_log()` RPC filters strictly on the caller's own `organization_id` (never NULL/global rows), an explicit event-type allowlist (never system/infra-only events), and a least-privilege permission gate (`roles:read` OR `roles:manage`, matching the existing "Acessos" tab condition). Explicit column projection — never raw JSONB — bounds future payload growth.
- **Integrity:** every audit write happens inside the same `SECURITY DEFINER` transaction as the state-changing mutation, so it can never be skipped or reordered by the Dart client. `remove_member` captures the target's email/role into local variables **before** the hard `DELETE`, since the audit row becomes the only surviving record of the removal.
- **Availability:** reuses the existing `idx_system_audit_log_org_time` partial index (`organization_id, occurred_at DESC WHERE organization_id IS NOT NULL`) — no new index required. Inserts are cheap single-row writes with no external calls.

Also removes the dead `system_audit_log_select_admin_policy` RLS policy, which checked a bare `user_role` JWT claim never emitted by the current `custom_access_token_hook` and was therefore permanently unreachable stale security configuration.

## Scope

- `_rbac_audit` (enhanced to auto-embed `actor_id`/`actor_email` from the JWT/`auth.users`, never from client-supplied payload).
- `deactivate_member`, `reactivate_member`, `update_member_role`, `remove_member`, `invite_user`, `revoke_invitation`, `accept_invitation` RPCs (instrumented).
- New RPC: `get_tenant_governance_log`.
- Removed: `system_audit_log_select_admin_policy`.

## Pre-conditions

- Two organizations exist (to verify tenant isolation).
- Org 1 has an Administrador (coarse `TENANT_ADMIN`, JWT permission `*`), an Auditor (JWT permission `roles:read` only), an Operador (no relevant permissions), and a target member.
- Org 2 has its own Administrador, used only to verify isolation.
- Test uses pgTAP inside an active transaction; all mutations roll back at the end.

## Test Cases

### 1. `deactivate_member` → `MEMBER_DEACTIVATED`
- **Action:** Admin deactivates a target member.
- **Expected:** Call succeeds; a `MEMBER_DEACTIVATED` row is written with `target_email` matching the target and `actor_email` matching the admin (auto-embedded, not client-supplied).

### 2. `reactivate_member` → `MEMBER_REACTIVATED`
- **Action:** Admin reactivates the same target.
- **Expected:** Exactly one `MEMBER_REACTIVATED` row is written.

### 3. `update_member_role` → `MEMBER_ROLE_CHANGED`
- **Action:** Admin changes the target's legacy role from `OPERATOR` to `AUDITOR`.
- **Expected:** The audit row's payload captures both `previous_role` and `new_role`.

### 4. `remove_member` → `MEMBER_REMOVED` (QA BLOCKER-3)
- **Action:** Admin removes the target member.
- **Expected:** The `user_roles` row is hard-deleted, but the `MEMBER_REMOVED` audit row still carries the correct `target_email` — proving the payload was captured from local variables before the `DELETE`, not read back from the (now-gone) row afterward.

### 5. System-only events never leak (QA BLOCKER-2)
- **Setup:** A system-level event (`ORGANIZATION_CREATE`) is inserted directly into `system_audit_log` with the same `organization_id` as Org 1.
- **Action:** Admin calls `get_tenant_governance_log`.
- **Expected:** The `ORGANIZATION_CREATE` row is absent from the results — the explicit event-type allowlist excludes it even though the org_id predicate alone would have matched.

### 6. Auditor default access (QA sign-off requirement)
- **Setup:** Impersonate a user holding only `roles:read` (no `roles:manage`, no `*`) — the Auditor persona's default seeded permission.
- **Action:** Call `get_tenant_governance_log`.
- **Expected:** Call succeeds (`lives_ok`) and returns the previously-logged events for the org.

### 7. Least-privilege denial
- **Setup:** Impersonate a user holding no relevant permission (Operador default).
- **Action:** Call `get_tenant_governance_log`.
- **Expected:** `throws_ok` with `insufficient_privilege` (`42501`).

### 8. Tenant isolation (INV-22)
- **Setup:** Impersonate Org 2's Administrador.
- **Action:** Call `get_tenant_governance_log`.
- **Expected:** Zero rows returned — none of Org 1's events are visible.

### 9. Dead policy removal (QA BLOCKER-1)
- **Action:** Query `pg_policies` for `system_audit_log_select_admin_policy`.
- **Expected:** Zero rows — the policy no longer exists.

## Post-conditions

All mutations roll back automatically at the end of the pgTAP transaction. No side effects.
