# Test Plan: 20260820000001_portal_state_transition.sql

## Feature Overview
Updates `register_portal_evidence` and `submit_portal_justification_only` to transition the queue status to `pending_peer_review` and revoke the carrier token to prevent double-submissions. Includes strict concurrency checks.

## Test Scope
- Verify queue transitions to `pending_peer_review`.
- Verify token is revoked (`revoked_at_utc` is set).
- Verify concurrency lock prevents double execution if state is not `disputed`.

## Rollback Plan
Since this is append-only, rollback implies a new migration restoring the original behavior.

## Sign-off
- Architect: Approved
- DB Admin: Approved
