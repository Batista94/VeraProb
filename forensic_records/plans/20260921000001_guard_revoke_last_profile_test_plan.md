# Forensic Test Plan: Guard Revoke Last Profile

**Migration:** 20260921000001_guard_revoke_last_profile.sql
**Author:** Antigravity
**Date:** 2026-07-08

## Invariants Covered
- **INV-22 (Tenant Isolation):** Leaving a user with zero profiles results in an undefined access state.
- **INV-3 (Append-Only):** The guard uses an exception to roll back the soft-revoke transaction atomically.

## Context
Revoking the last active profile of a user leaves them in a state where they are technically still in the organization but have no defined role, which could lead to privilege escalation via stale JWT claims. The evoke_tenant_role RPC now counts the remaining profiles and raises a P0001 (LastProfileGuard) exception if the user would be left with zero profiles.

## Test Scenarios (pgTAP)
1. **Multiple Profiles (Success):** Revoking one profile from a user with two active profiles succeeds.
2. **Last Profile Guard (Block):** Revoking the only remaining profile from a user is blocked by the LastProfileGuard exception.
3. **Rollback Verification:** The blocked revocation must atomically roll back any soft-revoke updates.
4. **Audit Trail Verification:** Blocked revocations must not generate ROLE_REVOKED audit log entries.
5. **Auto-Revoke Session Correlation:** Revoking a sensitive role correctly triggers session revocation for the target user if they still have other profiles left.