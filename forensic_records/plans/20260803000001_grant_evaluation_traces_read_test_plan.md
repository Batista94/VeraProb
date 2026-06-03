# Test Plan: 20260803000001_grant_evaluation_traces_read

**Migration:** `20260803000001_grant_evaluation_traces_read.sql`
**Author:** Council (Architect + QA/Security)
**Date:** 2026-08-03

## Context

Migration `20260717000009_grant_internal_governance_tables.sql` classified
`contractual_evaluation_traces` as Category C (Internal Governance), executing
`REVOKE ALL FROM public, anon, authenticated` and granting only to `service_role`.

This caused error **42501** (insufficient_privilege) when the `InvestigationModal`
attempted to read evaluation traces via the Data API as an `authenticated` user.

This migration re-grants `SELECT` to `authenticated`. The existing RLS policies
(corrected in `20260310210000`) enforce tenant isolation via
`(current_setting('request.jwt.claims', true)::json -> 'app_metadata' ->> 'org_id')::uuid`.

## Test Cases

### TC-1: Authenticated SELECT — Own Org (Happy Path)
- **Setup:** Insert an evaluation trace for `org_a`. Authenticate as user in `org_a`.
- **Action:** `SELECT * FROM contractual_evaluation_traces WHERE organization_id = org_a_id;`
- **Expected:** Rows returned matching `org_a`.
- **Invariants:** INV-DATA-API-GRANT, INV-2.

### TC-2: Authenticated SELECT — Cross-Tenant (INV-22 + INV-26)
- **Setup:** Insert an evaluation trace for `org_a`. Authenticate as user in `org_b`.
- **Action:** `SELECT * FROM contractual_evaluation_traces WHERE organization_id = org_a_id;`
- **Expected:** Zero rows returned (RLS blocks). No error exposed — 404 parity (INV-26).
- **Invariants:** INV-22 (tenant isolation), INV-26 (anti-oracle).

### TC-3: Authenticated INSERT — Still Permitted
- **Setup:** Authenticate as user in `org_a`.
- **Action:** `INSERT INTO contractual_evaluation_traces (...) VALUES (...);`
- **Expected:** Success (existing INSERT policy unchanged by this migration).
- **Invariants:** INV-3 (append-only — INSERT is the only allowed write op).

### TC-4: Authenticated UPDATE — Remains Blocked (INV-3)
- **Setup:** Insert a trace for `org_a`. Authenticate as user in `org_a`.
- **Action:** `UPDATE contractual_evaluation_traces SET engine_version = 'tampered' WHERE ...;`
- **Expected:** Error — `UPDATE` was `REVOKE`d in the original migration (20260305194500).
- **Invariants:** INV-3 (append-only immutability).

### TC-5: Authenticated DELETE — Remains Blocked (INV-3)
- **Setup:** Insert a trace for `org_a`. Authenticate as user in `org_a`.
- **Action:** `DELETE FROM contractual_evaluation_traces WHERE ...;`
- **Expected:** Error — `DELETE` was `REVOKE`d in the original migration (20260305194500).
- **Invariants:** INV-3 (append-only immutability).

### TC-6: Anon SELECT — Remains Blocked
- **Setup:** Insert a trace for `org_a`. Connect as `anon`.
- **Action:** `SELECT * FROM contractual_evaluation_traces;`
- **Expected:** Error or zero rows — `anon` has no grants.

## Rollback Strategy

```sql
REVOKE SELECT ON TABLE public.contractual_evaluation_traces FROM authenticated;
```

## Sign-Off

- [ ] Architect
- [ ] QA/Security
- [ ] Senior Developer
