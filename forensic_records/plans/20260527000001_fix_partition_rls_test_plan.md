# Test Plan: 20260527000001_fix_partition_rls

**Migration:** `supabase/migrations/20260527000001_fix_partition_rls.sql`
**Phase:** Security Hardening — Partition RLS Gap

## Problem Statement

PostgreSQL does NOT propagate parent-table RLS policies to partition tables when
a partition is queried directly by name. The four HASH partitions of
`sla_audit_ledger_v2` (`sla_audit_ledger_p0`–`p3`) had `rowsecurity = false`.
An authenticated session knowing or discovering a partition name could issue
`SELECT * FROM public.sla_audit_ledger_p0` and receive every tenant's ledger
entries with no filtering applied — a complete INV-22 bypass.

`spatial_ref_sys` (PostGIS) also lacked RLS, breaking the full-schema audit
invariant.

## INV Compliance

| INV   | Status | Detail |
|-------|--------|--------|
| INV-2  | Fixed  | Policies use `auth.jwt() -> 'app_metadata' ->> 'org_id'` — matches `custom_access_token_hook` injection path |
| INV-22 | Fixed  | Direct partition query no longer bypasses tenant filter |
| INV-DB | OK     | `ALTER TABLE ... ENABLE ROW LEVEL SECURITY` is non-blocking; `DROP POLICY IF EXISTS` + `CREATE POLICY` are non-destructive |

## Exploit Path Closed

**Vector:** `SELECT * FROM public.sla_audit_ledger_p0` executed by a session
whose JWT carries `org_id = <Org-B>` would have returned all rows including
those belonging to Org-A (and all other tenants) because `rowsecurity = false`
on the partition meant the `sla_audit_ledger_v2` parent policy was never
evaluated.

**Closure:** After this migration, Postgres evaluates the `FOR ALL` policy on
each partition independently, filtering by `organization_id =
(auth.jwt() -> 'app_metadata' ->> 'org_id')::UUID` regardless of whether the
query enters through the parent or a named partition.

## pgTAP Test Cases

### TC-1: RLS enabled on all four partitions

```sql
SELECT row_security_active('public', 'sla_audit_ledger_p0');
SELECT row_security_active('public', 'sla_audit_ledger_p1');
SELECT row_security_active('public', 'sla_audit_ledger_p2');
SELECT row_security_active('public', 'sla_audit_ledger_p3');
```

Assert: all return `true`.

### TC-2: Correct policy name on each partition

```sql
SELECT policies_are(
  'public', 'sla_audit_ledger_p0',
  ARRAY['Tenant Isolation: sla_audit_ledger_p0']
);
-- Repeat for p1, p2, p3
```

Assert: policy name matches exactly.

### TC-3: Partition direct-query isolation — Org-A cannot read Org-B rows via partition name

Setup:
- Insert a ledger row with `organization_id = <org_a_uuid>` (routed to its
  HASH partition, e.g. `p0` for testing purposes).
- Issue `SELECT * FROM public.sla_audit_ledger_p0` under a session with
  JWT `app_metadata.org_id = <org_b_uuid>`.

Assert: 0 rows returned.

### TC-4: Partition direct-query — tenant sees own rows

Setup:
- Insert a ledger row with `organization_id = <org_a_uuid>`.
- Issue `SELECT * FROM public.sla_audit_ledger_p0` under a session with
  JWT `app_metadata.org_id = <org_a_uuid>`.

Assert: 1 row returned (the inserted row).

### TC-5: INSERT blocked on wrong-tenant partition

Setup:
- Attempt `INSERT INTO public.sla_audit_ledger_p0 (..., organization_id) VALUES (..., <org_b_uuid>)`
  under a session with JWT `app_metadata.org_id = <org_a_uuid>`.

Assert: statement is rejected (RLS WITH CHECK violation).

### TC-6: Parent-table policy still works (regression guard)

Setup:
- INSERT a row via the parent table `sla_audit_ledger_v2` with
  `organization_id = <org_a_uuid>`.
- Query via parent under a session with `org_b_uuid`.

Assert: 0 rows returned. Confirms partition policy did not inadvertently
interfere with parent-level evaluation.

### TC-7: spatial_ref_sys — RLS enabled

```sql
SELECT row_security_active('public', 'spatial_ref_sys');
```

Assert: `true`.

### TC-8: spatial_ref_sys — authenticated user can read SRID data

- Issue `SELECT COUNT(*) FROM public.spatial_ref_sys` under any authenticated
  session.

Assert: count > 0 (PostGIS default SRIDs present).

### TC-9: spatial_ref_sys — unauthenticated (anon) SELECT permitted

- Issue `SELECT srid FROM public.spatial_ref_sys WHERE srid = 4326` under the
  `anon` role (permissive SELECT policy targets `TO public`).

Assert: 1 row returned (WGS 84 record exists).

## Structural Verification Checklist

- [x] No `DROP TABLE`, `DELETE`, `TRUNCATE`, or blocking `ALTER COLUMN` — INV-DB compliant
- [x] `DROP POLICY IF EXISTS` guards all `CREATE POLICY` statements (idempotent reapply)
- [x] All four partition policies use `FOR ALL` with both `USING` and `WITH CHECK` clauses
- [x] JWT path is `auth.jwt() -> 'app_metadata' ->> 'org_id'` — no `auth.uid()` (INV-2)
- [x] `spatial_ref_sys` policy is `FOR SELECT TO public USING (true)` — no tenant filter needed for static reference data
- [x] No modification to any previously merged migration (append-only)
