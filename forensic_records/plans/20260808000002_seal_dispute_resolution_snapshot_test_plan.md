# Test Plan: 20260808000002 — Seal dispute resolution snapshot

## Migration
`supabase/migrations/20260808000002_seal_dispute_resolution_snapshot.sql`

## Purpose
Creates a forensic evidence snapshot linked to an EXISTING ledger entry. Used exclusively by the `DISPUTE_OVERTURNED` arc: `resolve_dispute_handler` appends the `DISPUTE_OVERTURNED` ledger fact first, then calls this RPC (`seal_dispute_resolution_snapshot`) to attach the immutable snapshot to that entry.
Unlike `seal_forensic_evidence`, this function performs NO ledger append (maintaining INV-3: append-only). It freezes SLA rules and computes the integrity hash identically, so `verify_forensic_evidence` works without modification.

## Scope

| Object | Type | Roles | Permissions |
|--------|------|-------|-------------|
| `public.seal_dispute_resolution_snapshot` | FUNCTION | `authenticated`, `service_role` | EXECUTE |

## Invariants at Play

| ID | Rule | Description |
|----|------|-------------|
| INV-1 / INV-22 | Tenant isolation | `organization_id` JWT claims validation (insufficient_privilege on mismatched tenant) |
| INV-3 | Append-only ledger | Performs no ledger appends (relies on pre-existing entry) |
| INV-11 | Idempotency | Replay returns existing snapshot without creating duplicate |

## Verification SQL

```sql
-- 1. Verify function exists with expected signature
SELECT has_function(
  'public',
  'seal_dispute_resolution_snapshot',
  ARRAY['uuid', 'uuid', 'uuid', 'text', 'integer', 'timestamp with time zone', 'uuid', 'text']
);

-- 2. Verify security definer
SELECT is(
  (SELECT prosecdef FROM pg_proc WHERE proname = 'seal_dispute_resolution_snapshot'),
  true,
  'Function seal_dispute_resolution_snapshot is SECURITY DEFINER'
);

-- 3. Verify function privilege for authenticated role
SELECT ok(
  has_function_privilege('authenticated',
    'public.seal_dispute_resolution_snapshot(uuid, uuid, uuid, text, integer, timestamp with time zone, uuid, text)',
    'EXECUTE'),
  'authenticated role may execute seal_dispute_resolution_snapshot'
);

-- 4. Verify function privilege for service_role role
SELECT ok(
  has_function_privilege('service_role',
    'public.seal_dispute_resolution_snapshot(uuid, uuid, uuid, text, integer, timestamp with time zone, uuid, text)',
    'EXECUTE'),
  'service_role role may execute seal_dispute_resolution_snapshot'
);
```

## Acceptance Criteria

1. Function `seal_dispute_resolution_snapshot` exists with correct signature and is `SECURITY DEFINER`.
2. Execution privileges are granted to `authenticated` and `service_role`.
3. An existing ledger entry can have a dispute resolution snapshot sealed against it.
4. Idempotency is respected (re-executing with same key returns the existing snapshot).
5. Cross-tenant execution is rejected (SQLSTATE 42501) if caller's JWT org does not match `p_organization_id`.
6. `make test-db` passes with zero failures.
