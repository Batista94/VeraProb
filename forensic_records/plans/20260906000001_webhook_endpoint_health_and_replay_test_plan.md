# Test Plan: 20260906000001_webhook_endpoint_health_and_replay

## Goal
Verify that the `v_webhook_endpoint_health` view correctly rolls up webhook deliveries by status per endpoint and respects `security_invoker`.
Verify that the `webhook_manual_replay` RPC correctly validates tenant isolation (INV-1), resets the status of FAILED/DEAD logs, and enforces the 30-second rate limit.

## Scope
- View: `v_webhook_endpoint_health`
- Function: `webhook_manual_replay`

## Scenarios
1. **View Rollup**: Ensure counts for PENDING, DELIVERING, SUCCESS, FAILED, DEAD, and total logs are accurately calculated per endpoint.
2. **View Tenant Isolation**: Ensure a user can only see the health of endpoints belonging to their organization via RLS (`security_invoker = true`).
3. **RPC Authorization**: Ensure only users with `TENANT_ADMIN` role can execute `webhook_manual_replay`.
4. **RPC Tenant Isolation (INV-1 / Anti-Oracle)**: Attempting to replay a log from another organization must fail indistinguishably from not-found (`SQLSTATE P0002`, message "Webhook delivery log not found").
5. **RPC Status Validation**: Attempting to replay a log in `SUCCESS`, `PENDING`, or `DELIVERING` must fail (`P0001` → domain message in PT).
6. **RPC Success**: Replaying a `FAILED` or `DEAD` log must succeed, resetting it to `PENDING` with 0 attempts and clearing `last_error`.
7. **RPC Rate Limit**: After a successful replay kicks an endpoint, a second replay of a *distinct* still-replayable log on the **same endpoint** within 30 seconds must fail (`P0001`).

## Non-obvious test constraints (verified against local DB)
- **Ledger seed type**: use a NON-terminal `sla_audit_ledger_v2.type` (e.g. `OCCURRENCE_REGISTERED`). Terminal verdict types (`VERDICT_SEALED`, `VERDICT_REFUSED`, `DISPUTE_*`, `SANCTION_ACKNOWLEDGED`) fire the `enqueue_verdict_webhooks` trigger, which inserts phantom PENDING `webhook_delivery_logs` and corrupts the rollup assertion.
- **Rate-limit assertion** must target a **different** log than the one already replayed: the first replay flips its own log to `PENDING`, so re-replaying it would trip the status check (step 5) before the rate-limit check (step 7). A separate `DEAD` log on the same endpoint isolates the rate-limit path.
- **Error codes**: `webhook_manual_replay` raises only VALID PostgreSQL condition names / SQLSTATEs (`insufficient_privilege`, `no_data_found`, bare `P0001`). Custom names like `not_found`/`rate_limit_exceeded` raise `unrecognized exception condition` at runtime, masking the intended message.
