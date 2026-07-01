# Test Plan: Enqueue Verdict Webhooks Trigger (20260904000004)

## Objective
Verify that inserting terminal verdicts into `sla_audit_ledger_v2` triggers the fan-out enqueue process to `webhook_delivery_logs`.

## Verification Steps
1. Create a `webhook_endpoints` row.
2. Insert a `VERDICT_SEALED` fact into `sla_audit_ledger_v2`.
3. Select from `webhook_delivery_logs` -> MUST have exactly one row matching the `ledger_entry_id` with `signing_key_id` as NULL.
4. Add another active endpoint and insert `DISPUTE_ACCEPTED` -> MUST fan-out and insert two rows in `webhook_delivery_logs`.
