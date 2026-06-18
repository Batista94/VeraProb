# Test Plan: 20260820000001_get_financial_impact_summary.sql

## Goal
Verify the aggregation of sanction review queue entries for the financial impact dashboard.

## Scope
- Creation of `get_financial_impact_summary` RPC.

## Checks
1. [x] **Tríade CIA**: Must be SECURITY DEFINER.
2. [x] **INV-2 (Tenant Isolation)**: Must strictly validate `request.jwt.claims -> app_metadata -> org_id`.
3. [x] **Math**: Summing `fine_cents` correctly by status groups.
