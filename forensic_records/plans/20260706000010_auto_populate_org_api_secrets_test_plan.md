# Test Plan — 20260706000010_auto_populate_org_api_secrets

Migration: `supabase/migrations/20260706000010_auto_populate_org_api_secrets.sql`  
INV: INV-3, INV-6, INV-22, INV-28

## Scope

RPC `super_admin_create_organization` now atomically generates and stores the
org API secret inside the same transaction, returning
`TABLE(org_id UUID, plaintext_secret TEXT)` instead of a bare UUID.
The old Edge Function path (`generate-org-secret`) is retired.

---

## DB Tests (pgTAP — `supabase/tests/`)

| ID | Scenario | Expected |
|----|----------|---------|
| DB-01 | Call RPC with valid params (service_role) | Returns exactly 1 row with `org_id` (UUID) and `plaintext_secret` (64-char hex) |
| DB-02 | `org_api_secrets` row exists after call | `organization_id` matches returned `org_id`, `version = 1`, `revoked_at IS NULL` |
| DB-03 | `secret_hash` stored is SHA-256 of `plaintext_secret` | `encode(digest(plaintext_secret, 'sha256'), 'hex') = secret_hash` |
| DB-04 | Plaintext NOT stored in `org_api_secrets` | `secret_hash != plaintext_secret` |
| DB-05 | Duplicate CNPJ raises 23505 | Transaction rolls back; no `org_api_secrets` row created |
| DB-06 | Call without super_admin JWT claim raises `insufficient_privilege` | Exception code = `42501` |
| DB-07 | Immutability trigger blocks UPDATE on `secret_hash` | Exception raised, row unchanged |
| DB-08 | `org_api_secrets.created_at` is `TIMESTAMPTZ` and non-null | INV-6 |
| DB-09 | `organizations` row and `org_api_secrets` row committed atomically | No org row without corresponding secret row |
| DB-10 | `tenant_billing_events` row inserted with `event_type = 'ORG_CREATED'` | Billing event present, INV-3 |

---

## Unit Tests (Dart — `test/application/super_admin/`)

| ID | Scenario | Expected |
|----|----------|---------|
| UT-01 | `handle()` returns `CreateOrganizationResult.orgApiSecret` non-null (64-char hex) | Secret propagated from RPC response |
| UT-02 | `handle()` throws `IntegrityException` when repo returns null secret | INV-10: no silent degradation |
| UT-03 | `handle()` throws `IntegrityException` when repo returns empty-string secret | INV-10 |
| UT-04 | `_provisionOrganization` passes correct params to `ISuperAdminRepository` | Command fields map 1:1 to repo call |
| UT-05 | `ISuperAdminRepository.createOrganization` returns `(orgId, plaintext)` record | Interface updated — infra parses TABLE response |

---

## Widget Tests (Dart — `test/features/super_admin/presentation/screens/`)

| ID | Scenario | Expected |
|----|----------|---------|
| WD-01 | Success dialog renders `_SecretRevealSection` when `orgApiSecret` is non-null | Section visible, label = "Segredo inicial (exibido apenas uma vez)" |
| WD-02 | Success dialog does NOT render `_SecretRevealSection` when `orgApiSecret` is null | Section absent from widget tree |
| WD-03 | Copy button sets clipboard to `orgApiSecret` value | Clipboard contains the secret |

---

## Acceptance Criteria

- [ ] `super_admin_create_organization` RPC returns `(org_id, plaintext_secret)` (not bare UUID)
- [ ] `org_api_secrets` row created atomically in same transaction as `organizations` insert
- [ ] SHA-256 hash stored, plaintext never persisted
- [ ] Dart handler propagates secret to `CreateOrganizationResult.orgApiSecret`
- [ ] `IntegrityException` thrown (not silent null) when secret absent from RPC response
- [ ] Success wizard shows label "Segredo inicial (exibido apenas uma vez)"
- [ ] No regression on existing CNPJ duplicate detection (23505 → `DomainException`)
- [ ] `flutter analyze` zero warnings after changes
