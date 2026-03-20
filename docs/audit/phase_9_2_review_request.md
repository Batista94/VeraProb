# Phase 9.2 — SuperAdmin Portal: Lead Reviewer [GO/NO-GO] Verdict

## INV-22 Compliance Gate

**Requesting Entity:** Product Owner / Engineering Lead
**Date Submitted:** 2026-03-19
**Scope:** Phase 9.2 — SuperAdmin Portal (full implementation)
**INV-22 Trigger:** Modifications to `custom_access_token_hook` (core RLS logic) and new table `super_admin_users`.

---

## Changes Requiring [GO] Verdict

### 1. `custom_access_token_hook` Extension (`20260405000001`)
The existing hook (from `20260402000002_contractor_viewer_dual_key.sql`) is extended to check
`super_admin_users` FIRST. If the user is found there, the hook short-circuits and injects
`super_admin: true`, setting `org_id/role/contractor_id` to null.

**Defense-in-depth:** SuperAdmin never inherits a tenant org context.

**Risk:** Bug in ordering could give SuperAdmin a tenant role. Mitigation: `IF FOUND` branch
exits immediately after injecting `super_admin: true` — the `user_roles` lookup never executes.

### 2. New Table: `super_admin_users`
Separate from `user_roles` (D1 decision: `user_roles` requires `organization_id NOT NULL`).
No RLS for `authenticated` — only readable by `supabase_auth_admin` for the hook.

### 3. `organizations` Table Additions (`20260405000001`)
Five new nullable columns: `legal_name`, `cnpj`, `plan_type`, `max_vehicles`, `max_active_contracts`.
Partial unique index on `cnpj`. Non-breaking (all nullable or have defaults).

### 4. New RPC: `super_admin_create_organization` (`20260405000005`)
SECURITY DEFINER. Validates `super_admin: true` claim in JWT. Inserts org + billing event atomically.
**Risk:** If JWT validation logic has a bug, a non-SuperAdmin could call it.
**Mitigation:** Double check: `(auth.jwt() -> 'app_metadata' ->> 'super_admin') = 'true'` must pass.

### 5. New RPC: `super_admin_invite_first_admin` (`20260405000005`)
SECURITY DEFINER. Same JWT validation. Bypasses `invite_user` (which requires TENANT_ADMIN JWT).
Explicitly inserts into `invitations` with a provided `p_org_id`.

### 6. `super_admin_tenant_health_view` (`20260405000003`)
Cross-tenant read via service_role. No GRANT to authenticated/anon.
**Risk:** Accidental GRANT could expose all org data.
**Mitigation:** No GRANT statement in migration. PostgREST only exposes via service_role client.

### 7. `organizations` RLS Hardening (`20260405000006`)
Adds `AND (auth.jwt() -> 'app_metadata' ->> 'super_admin') IS DISTINCT FROM 'true'` to SELECT
policy. Prevents SuperAdmin JWT from reading org data via anon client.

---

## Security Checklist

| Check | Status |
|---|---|
| `super_admin_users` has no PUBLIC GRANT | ✓ Migration grants only to `supabase_auth_admin` |
| Hook checks `super_admin_users` BEFORE `user_roles` | ✓ |
| SuperAdmin JWT has `org_id = null`, `role = null`, `contractor_id = null` | ✓ |
| Health view has no GRANT to authenticated/anon | ✓ |
| Both RPCs validate `super_admin: true` claim server-side | ✓ |
| service_role client never passed to tenant providers | ✓ D3 decision enforced in providers |
| INV-24 idempotency: CNPJ unique index prevents duplicate orgs | ✓ |

---

## Verdict

**[ ] [GO] — Approved to apply migrations and merge**
**[ ] [NO-GO] — Changes required before approval**

**Verdict by:** _____________________ (Lead Reviewer)
**Date:** _____________________
**Notes:**
