# Forensic Test Plan: Invite Tenant Role Provisioning

## Target
`supabase/migrations/20260918000004_invite_tenant_role_provisioning.sql`

## Overview
This plan verifies the fix for Bug 3 (Privilege Escalation Prevention) and Bug 4 (Direct Provisioning without four-eyes). It ensures that users with `users:manage` can invite other users, but cannot invite a `TENANT_ADMIN` or a profile with admin powers. It also ensures that `accept_invitation` correctly provisions the fine-grained `tenant_role_id` into `user_tenant_roles`.

## Scenarios Covered

1. **Invite with users:manage (Happy Path)**
   - **Condition:** An OPERATOR with the `users:manage` permission invokes `invite_user` to invite an AUDITOR.
   - **Expected Result:** The invitation is successfully created with `tenant_role_id` populated.

2. **Privilege Escalation Prevention (Bug 3)**
   - **Condition:** An OPERATOR with the `users:manage` permission invokes `invite_user` to invite a `TENANT_ADMIN` (or a system admin profile).
   - **Expected Result:** Exception is raised `Unauthorized: Only a TENANT_ADMIN can invite another Admin`.

3. **Missing Permission (Bug 3)**
   - **Condition:** An OPERATOR WITHOUT the `users:manage` permission invokes `invite_user`.
   - **Expected Result:** Exception is raised `Unauthorized: TENANT_ADMIN or users:manage permission required to invite users`.

4. **Direct Provisioning on Accept (Bug 4)**
   - **Condition:** A user accepts an invitation that has a `tenant_role_id`.
   - **Expected Result:** The user gets a row in `user_roles` AND a row in `user_tenant_roles` with the specified `tenant_role_id`, without going through the `role_change_requests` queue.

## Invariants Guarded
- **INV-1 & INV-22:** Tenant isolation (users cannot grant roles from other tenants).
- **INV-3:** Audit trail (MEMBER_INVITED and INVITATION_ACCEPTED events are properly logged).
- **Anti-Escalation:** No user can elevate privileges beyond their own maximum boundaries.
