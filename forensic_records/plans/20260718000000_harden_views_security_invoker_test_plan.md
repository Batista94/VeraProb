# Test Plan: 20260718000000 — Device Heartbeat Status View SECURITY INVOKER Hardening

**Migration:** `supabase/migrations/20260718000000_harden_views_security_invoker.sql`  
**Invariants:** INV-2, INV-11, INV-22, INV-DB  
**Risk:** MEDIUM — view lacks security_invoker options which allows bypassing RLS on base tables.

---

## Exploit Closed

| Vector | Before | After |
|--------|--------|-------|
| Direct `SELECT` on `vw_device_heartbeat_status` | Bypassed RLS on `canonical_facts` (executed as owner `postgres`) | Enforces caller's RLS policies on `canonical_facts` (when queried directly) |
| View security settings | Missing `security_invoker` | Set to `security_invoker = true` |

---

## pgTAP Tests

### T1 — View exists after migration
Verify that `vw_device_heartbeat_status` view exists in the `public` schema.

```sql
SELECT has_view('public', 'vw_device_heartbeat_status', 'vw_device_heartbeat_status view exists');
```

### T2 — View has security_invoker = true
Verify that the `security_invoker` option is applied on the view.

```sql
SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = 'vw_device_heartbeat_status'
      AND c.reloptions::text LIKE '%security_invoker=true%'
  ),
  'vw_device_heartbeat_status must have security_invoker=true (INV-11)'
);
```

### T3 — View direct access is revoked from PUBLIC, authenticated, anon roles
Verify that standard API roles do not have direct access to the view.

```sql
SELECT table_privs_are('public', 'vw_device_heartbeat_status', 'anon', ARRAY[]::text[], 'anon has no privileges on vw_device_heartbeat_status');
SELECT table_privs_are('public', 'vw_device_heartbeat_status', 'authenticated', ARRAY[]::text[], 'authenticated has no privileges on vw_device_heartbeat_status');
SELECT table_privs_are('public', 'vw_device_heartbeat_status', 'service_role', ARRAY['SELECT'], 'service_role has SELECT privilege on vw_device_heartbeat_status');
```

### T4 — Dependent RPC exists
Verify that the `get_device_heartbeat_status` function exists.

```sql
SELECT has_function('public', 'get_device_heartbeat_status', ARRAY['uuid'], 'get_device_heartbeat_status(uuid) exists');
```

### T5 — Dependent RPC execution permissions
Verify that `authenticated` has execute permissions and `PUBLIC` does not.

```sql
SELECT ok(
  has_function_privilege('authenticated', 'get_device_heartbeat_status(uuid)', 'execute'),
  'authenticated role can execute get_device_heartbeat_status'
);
SELECT ok(
  NOT has_function_privilege('anon', 'get_device_heartbeat_status(uuid)', 'execute'),
  'anon role cannot execute get_device_heartbeat_status'
);
```

---

## Rollback

`DROP VIEW IF EXISTS public.vw_device_heartbeat_status CASCADE;` then re-run `20260501000002_heartbeat_monitor_view.sql`.  
No base table data is affected.
