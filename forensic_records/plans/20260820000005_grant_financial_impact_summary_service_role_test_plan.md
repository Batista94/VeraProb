# Test Plan: 20260820000005_grant_financial_impact_summary_service_role.sql

## Feature Overview
Grants EXECUTE permission on `get_financial_impact_summary` RPC to the `service_role` role. This resolves permission denied errors during E2E testing and background administrative tasks that run as `service_role`.

## Test Scope
- Verify that `service_role` can successfully execute the `get_financial_impact_summary(uuid)` RPC.
- Ensure that the E2E test suite `test/integration/e2e/sla_audit_e2e_postgres_test.dart` passes Stage 8 UI Dashboard Query Coverage without permission denied errors.

## Rollback Plan
Create a migration to revoke `execute` on function `get_financial_impact_summary(uuid)` from `service_role`.

## Sign-off
- Architect: Approved
- DB Admin: Approved
