# Test Plan: 20260906000001_webhook_endpoint_health_and_replay

## Goal
Verify that the `v_webhook_endpoint_health` view correctly rolls up webhook deliveries by status per endpoint and respects `security_invoker`.
Verify that the `webhook_manual_replay` RPC correctly validates tenant isolation (INV-1), resets the status of FAILED/DEAD logs, and enforces the 30-second rate limit.

## Scope
- View: `v_webhook_endpoint_health`
- Function: `webhook_manual_replay`

## Scenarios
1. **View Rollup**: Ensure counts for PENDING, DELIVERING, SUCCESS, FAILED, DEAD, and total logs are accurately calculated per endpoint.
2. **View Tenant Isolation**: Ensure a user can only see the health of endpoints belonging to their organization via RLS.
3. **RPC Authorization**: Ensure only users with `TENANT_ADMIN` role can execute `webhook_manual_replay`.
4. **RPC Tenant Isolation (INV-1 / Anti-Oracle)**: Attempting to replay a log from another organization must fail with `not_found`.
5. **RPC Status Validation**: Attempting to replay a log in `SUCCESS`, `PENDING`, or `DELIVERING` must fail.
6. **RPC Success**: Replaying a `FAILED` or `DEAD` log must succeed, resetting it to `PENDING` with 0 attempts and clearing `last_error`.
7. **RPC Rate Limit**: Attempting a second replay on an endpoint whose `last_kick_at` is within 30 seconds must fail.
