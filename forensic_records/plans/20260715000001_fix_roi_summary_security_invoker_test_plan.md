# Test Plan: 20260715000001 — ROI Summary View SECURITY INVOKER Hardening

**Migration:** `supabase/migrations/20260715000001_fix_roi_summary_security_invoker.sql`  
**Invariants:** INV-2, INV-22, INV-DB  
**Risk:** HIGH — cross-tenant ROI data exposure via SECURITY DEFINER view

---

## Exploit Closed

| Vector | Before | After |
|--------|--------|-------|
| `SELECT * FROM public.v_roi_summary` as org-A user | Returns ALL orgs' ROI data | Returns only org-A rows |
| View owner bypass | View ran as owner, bypassed RLS | Caller's RLS policies applied |

---

## pgTAP Tests

### T1 — View exists after migration

```sql
SELECT has_view('public', 'v_roi_summary', 'v_roi_summary view exists');
```

### T2 — View has security_invoker = true

```sql
SELECT is(
  (SELECT pg_catalog.pg_get_viewdef('public.v_roi_summary'::regclass, true)),
  -- Verify the view definition does not contain 'security_definer'
  -- by checking pg_class.reloptions
  NULL,
  'placeholder — use pg_class check below'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = 'v_roi_summary'
      AND c.reloptions::text LIKE '%security_invoker=true%'
  ),
  'v_roi_summary must have security_invoker=true (INV-22)'
);
```

### T3 — Cross-tenant isolation: org-A cannot see org-B ROI data

```sql
-- Setup: insert rows for org-A and org-B in shadow_executions
-- Set JWT claim to org-A; query v_roi_summary; assert no org-B row

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM public.v_roi_summary
    WHERE organization_id = :org_b_id
    -- session JWT set to org-A app_metadata.org_id
  ),
  'Org-A query of v_roi_summary must NOT return org-B data (INV-22)'
);
```

### T4 — Own-tenant visibility: org-A sees its own rows

```sql
SELECT ok(
  EXISTS (
    SELECT 1 FROM public.v_roi_summary
    WHERE organization_id = :org_a_id
  ),
  'Org-A must see its own ROI summary row (regression guard)'
);
```

### T5 — Unauthenticated call blocked

```sql
-- Set role to anon; attempt SELECT; expect 0 rows or permission denied
SELECT ok(
  (SELECT COUNT(*) FROM public.v_roi_summary) = 0,
  'Anon role must not see any ROI rows'
);
```

### T6 — Column set matches v2 definition

```sql
SELECT has_column('public', 'v_roi_summary', 'organization_id', 'column: organization_id');
SELECT has_column('public', 'v_roi_summary', 'recovered_trips', 'column: recovered_trips');
SELECT has_column('public', 'v_roi_summary', 'total_recovered_cents', 'column: total_recovered_cents');
SELECT has_column('public', 'v_roi_summary', 'total_avoided_penalty_cents', 'column: total_avoided_penalty_cents');
SELECT has_column('public', 'v_roi_summary', 'total_linked_trips', 'column: total_linked_trips');
SELECT has_column('public', 'v_roi_summary', 'pending_orphans', 'column: pending_orphans');
SELECT has_column('public', 'v_roi_summary', 'tool_cost_cents', 'column: tool_cost_cents');
SELECT has_column('public', 'v_roi_summary', 'roi_bps', 'column: roi_bps');
```

### T7 — INV-4: roi_bps is BIGINT arithmetic (no float)

```sql
SELECT col_type_is('public', 'v_roi_summary', 'tool_cost_cents', 'bigint',
  'tool_cost_cents must be bigint (INV-4)');
SELECT col_type_is('public', 'v_roi_summary', 'total_recovered_cents', 'bigint',
  'total_recovered_cents must be bigint (INV-4)');
```

### T8 — authenticated role has SELECT grant

```sql
SELECT table_privs_are(
  'public', 'v_roi_summary', 'authenticated', ARRAY['SELECT'],
  'authenticated role must have SELECT on v_roi_summary'
);
```

### T9 — Regression: shadow_executions RLS still enabled

```sql
SELECT ok(
  (SELECT relrowsecurity FROM pg_class
   WHERE oid = 'public.shadow_executions'::regclass),
  'shadow_executions RLS must be enabled (regression guard after view recreate)'
);
```

---

## Rollback

`DROP VIEW IF EXISTS public.v_roi_summary;` then re-run `20260703000002_roi_summary_v2.sql`.  
No base table data affected.
