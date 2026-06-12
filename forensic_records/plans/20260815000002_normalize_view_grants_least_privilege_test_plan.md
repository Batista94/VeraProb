# Test Plan — 20260815000002_normalize_view_grants_least_privilege

**Migration:** `supabase/migrations/20260815000002_normalize_view_grants_least_privilege.sql`
**Type:** RBAC grant normalization (no DDL). Append-only.
**Invariants:** INV-2, INV-22, INV-DATA-API-GRANT.

## Context

`20260719000000` granted service_role SELECT on `contractors_view` /
`invitations_view` / `v_roi_summary` but revoked the leftover privileges only
`FROM public, anon, authenticated` — never from service_role. service_role kept
engine-version-dependent leftovers (REFERENCES / TRIGGER / TRUNCATE), yielding a
non-deterministic ACL. The companion pgTAP over-asserted ALL 7 privileges, so a
clean `supabase db reset` failed 3 assertions on engines that do not leak.

This migration pins service_role to exactly SELECT (least privilege; these are
read-only masking / summary views) and the `20260719000000` test is corrected to
assert `['SELECT']`.

## Assertions (pgTAP — `supabase/tests/20260815000002_*_test.sql`)

| # | Assertion | Rationale |
|---|-----------|-----------|
| V1 | service_role privileges on `contractors_view` == `['SELECT']` | least privilege, deterministic |
| V2 | service_role privileges on `invitations_view` == `['SELECT']` | least privilege, deterministic |
| V3 | service_role privileges on `v_roi_summary` == `['SELECT']` | least privilege, deterministic |
| V4 | authenticated privileges on `contractors_view` == `['SELECT']` | unchanged read access |
| V5 | anon has NO privileges on `contractors_view` | INV-22 (PII not anon-readable) |
| V6 | anon has NO privileges on `invitations_view` | INV-22 |
| V7 | anon has NO privileges on `v_roi_summary` | INV-22 |
| V8 | service_role privileges on `vw_device_heartbeat_status` == `['SELECT']` | least privilege, deterministic |
| V9 | authenticated has NO privileges on `vw_device_heartbeat_status` | backend-only view |
| V10 | anon has NO privileges on `vw_device_heartbeat_status` | INV-22 |

## Verification

- `supabase db reset` → `make test-db` green (incl. corrected `20260719000000` test).
- Re-query: `\dp public.contractors_view` shows service_role with `r` (SELECT) only.
