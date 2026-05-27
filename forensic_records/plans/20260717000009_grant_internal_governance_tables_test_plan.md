# Test Plan: 20260717000009_grant_internal_governance_tables

## Objective
Verify that Internal-Governance tables have the exact required grants (ALL to `service_role`), and NO grants to `anon`, `authenticated`, or `public`.

## Tables to verify:
* public.raw_telemetry_payloads
* public.asset_status_events
* public.canonical_facts
* public.audit_packages
* public.org_quota_warnings
* public.ingestion_alerts
* public.contractual_evaluation_traces
* public.contractual_financial_snapshot_v2
* public.execution_state_transitions

## Test Steps
1. Execute pgTAP tests to check table privileges for `authenticated`, `anon`, and `service_role`.
2. Confirm `service_role` has SELECT, INSERT, UPDATE, DELETE.
3. Confirm `authenticated` has NO privileges (not SELECT, not INSERT, not UPDATE, not DELETE).
4. Confirm `anon` has NO privileges.
