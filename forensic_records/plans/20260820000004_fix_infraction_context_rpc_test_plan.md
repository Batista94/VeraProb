# Test Plan: 20260820000004_fix_infraction_context_rpc.sql

## Feature Overview
Fixes `read_infraction_context` RPC so it reads `measured_value` and `threshold_value` correctly from `verdict_evidence`, avoiding using `delta_value` and causing data discrepancies. Prioritizes `address` over coordinates for location label.

## Test Scope
- Run `read_infraction_context` and verify `measured_value` equals `89` (rounding `88.5`).
- Verify location uses string address if present.

## Rollback Plan
Create migration to restore `read_infraction_context` to read from `delta_value`.

## Sign-off
- Architect: Approved
- DB Admin: Approved
