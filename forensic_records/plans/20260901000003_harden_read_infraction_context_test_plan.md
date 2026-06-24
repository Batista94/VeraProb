# Test Plan: 20260901000003_harden_read_infraction_context.sql

## Overview
This migration implements data masking (Gap 3) for the infraction context:
- In `read_infraction_context`, if the requested token's associated queue entry is NOT in `disputed` status, return the essential fields (such as `record_id`, `status`, and `occurred_at_utc`), but mask all sensitive information (like coordinates, plate, fines, values, and location labels) with `NULL`.
- Prevents data leakage of settled or pending infractions to external portal users.

## Invariant Checks
- **INV-22 (Tenant Isolation):** The token checks and queue retrievals are securely bound by the corresponding `organization_id`.
- **INV-26 (Error Parity / Anti-Oracle):** Invalid tokens throw `insufficient_privilege` to prevent token enumeration.

## Verification Steps
1. In the corresponding pgTAP test, create a token associated with a `pending` queue entry, and another associated with a `disputed` queue entry.
2. Call `read_infraction_context` for the `disputed` entry, and assert that fields like `asset_identifier` (plate) and `penalty_value_cents` are returned with correct values.
3. Call `read_infraction_context` for the `pending` entry, and assert that the same fields return `NULL`, while `record_id` and `status` remain visible.
