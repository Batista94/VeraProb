# Test Plan: 20260822000001_fix_financial_impact_security_bypass.sql

**Governing Migration:** `supabase/migrations/20260822000001_fix_financial_impact_security_bypass.sql`
**Companion pgTAP:** `supabase/tests/20260822000001_fix_financial_impact_security_bypass_test.sql`
**Invariants Checked:** INV-2, INV-22

## Problem Fixed

The previous implementation of `get_financial_impact_summary` used `current_user IN ('service_role', 'postgres')` to bypass tenant isolation. Because pgTAP always runs as the `postgres` superuser, every test case — including the IDOR security assertions (TC4/TC8/TC9) — was silently bypassed. This migration replaces the role-name check with a JWT-claims presence check so the tenant isolation guard is exercised in all non-backend call contexts.

## Correct Bypass Logic

1. No JWT context (`request.jwt.claims` is NULL or empty) → trusted backend call, bypass OK.
2. JWT role claim = `service_role` → Supabase Edge Function with service_role key, bypass OK.
3. JWT present with `app_metadata.org_id` → enforce tenant isolation (org_id must match `p_org_id`).
4. JWT present but no `org_id` (anon, empty metadata) → raise `42501`.

## Scenarios

1. **TC4: IDOR (INV-2/INV-22)**
   - Condition: Authenticated JWT with Tenant A's `org_id` calls the function with Tenant B's `p_org_id`.
   - Expected: `42501` — `Access denied. Tenant isolation violation (INV-2).`

2. **TC8: Anon JWT (INV-2)**
   - Condition: JWT context present with `role: anon` and no `app_metadata`.
   - Expected: `42501` — `Access denied. Tenant isolation violation (INV-2).`

3. **TC9: Empty app_metadata (INV-2)**
   - Condition: Authenticated JWT with `app_metadata: {}` (no `org_id` key).
   - Expected: `42501` — `Access denied. Tenant isolation violation (INV-2).`

## Go/No-Go Gate

All three TC assertions must return `throws_ok` PASS before merge to main.
