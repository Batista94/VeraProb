# Test Plan — 20260602000001_fix_rls_public_role_policies

**Migration:** `supabase/migrations/20260602000001_fix_rls_public_role_policies.sql`
**Invariants:** INV-1, INV-2, INV-3, INV-22, INV-26
**Risk:** Medium-High — alters RLS policies and INSERT check rules on tenant-facing data.

---

## Objective

Verify that RLS policies that were scoped to the public role or had always-true conditions have been hardened. This involves confirming that:
1. Always-true policies on `idempotency_keys`, `telegram_chat_bindings`, `telegram_pending_links`, `telegram_user_consents`, `telegram_binding_tokens`, `justification_recomputation_signals`, and `justification_submission_tokens` are dropped.
2. Client-role privileges on `spatial_ref_sys` are revoked.
3. Service-only table insertion policies are dropped.
4. Client-facing table insertion policies are correctly scoped to authenticated users with tenant isolation checks.
5. Always-true financial snapshot policies are dropped.

---

## Pre-conditions

- Local Supabase running (`supabase start`)
- Migration applied (`supabase db reset`)

---

## Test Cases

### TC-1: Revocation on `spatial_ref_sys`
Verify that `anon` and `authenticated` roles do not have `SELECT` privilege on `public.spatial_ref_sys` if it exists.

### TC-2: Drop Always-True Policies
Verify that the `_service_all` and `_insert_service` policies with `USING(true)` or `WITH CHECK(true)` have been dropped from their respective tables.

### TC-3: Restrictive Deny-All Policies
Verify that `telegram_pending_links` and `telegram_user_consents` have restrictive deny-all policies for authenticated users.

### TC-4: Org-Isolated Insertion Policies
Verify that `sanction_review_queue`, `shadow_verdicts`, `telegram_evidence_links`, and `telegram_evidence_uploads` have `_insert_authenticated` policies that filter on the caller's JWT organizational claims.

### TC-5: Tenant Isolation Behavioral Verification
- An authenticated user inserting rows into `sanction_review_queue` or `shadow_verdicts` with their own `organization_id` (matching their JWT) is allowed.
- An authenticated user trying to insert rows into `sanction_review_queue` or `shadow_verdicts targeting another tenant's `organization_id` (foreign org UUID) is blocked with an RLS error.

---

## pgTAP Verification

Run the pgTAP test:
```bash
make test-db
```
The test suite in `supabase/tests/20260602000001_fix_rls_public_role_policies_test.sql` automates all these checks.

---

## Rollback

If these policy adjustments break app insertions:
1. Re-apply a less restrictive policy temporarily.
2. Verify the JWT claim nesting path (e.g. `auth.jwt() ->> 'organization_id'` vs `auth.jwt() -> 'app_metadata' ->> 'org_id'`).
