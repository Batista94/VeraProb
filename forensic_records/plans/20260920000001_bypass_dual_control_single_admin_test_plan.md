# Forensic Test Plan: Bypass Dual Control for Single Admin

**Migration:** 20260920000001_bypass_dual_control_single_admin.sql
**Author:** Antigravity
**Date:** 2026-07-08

## Invariants Covered
- **INV-3 (Append-Only):** Ensures bypass skips role_change_requests logic appropriately without mutating old records.
- **INV-22 (Tenant Isolation):** Ensures approval count check respects organization_id strictly.

## Context
Organizations with only 1 Administrator cannot use the "four-eyes" (role_change_requests) approval flow because there is no second admin to approve the changes. We added _rbac_count_approvers to bypass the approval queue (executing the role grant immediately) if the org has <= 1 approver.

## Test Scenarios (pgTAP)
1. **Single Admin Bypass:** Admin creates a request in an org with 1 admin. The request is processed immediately, returning the UUID of the newly assigned/created role.
2. **Multiple Admins Enqueue:** Admin creates a request in an org with >= 2 admins. The request must go to PENDING state in ole_change_requests.
3. **Count Verification:** _rbac_count_approvers accurately counts both global system admins and custom TENANT_ADMIN role assignments for the specific tenant.