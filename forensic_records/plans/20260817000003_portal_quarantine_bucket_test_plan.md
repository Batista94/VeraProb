# Test Plan: portal_quarantine_bucket (Sprint A M3 — Portal Submissão)

## Migration Coverage

| Migration | pgTAP File | Status |
|-----------|-----------|--------|
| `20260817000003_portal_quarantine_bucket.sql` | `20260817000003_portal_quarantine_bucket_test.sql` | ✅ |

## Intent

Private staging bucket `dispute-evidence-portal` where untrusted carrier
counter-evidence lands before server-side re-hashing (INV-9). Authorization is
**signed-URL only**: the carrier has no JWT, so the upload is gated by a
short-lived signed upload URL minted by `portal-submit-request` for the path
`{token_id}/{submission_uuid}.ext` (no org_id — anti-inference, INV-22). A signed
upload URL bypasses RLS by design, so there are deliberately **no anon/authenticated
storage.objects policies**. service_role (finalize) reads directly; clients never
touch the bucket. Orphans swept after 72h (Phase 10.9 hook).

## Test Scenarios (5 assertions)

| # | Category | Scenario | Assertion | INV |
|---|----------|----------|-----------|-----|
| B1 | Existence | bucket exists | `EXISTS` | - |
| B2 | Security | bucket is private | `NOT public` | INV-2 |
| B3 | Availability | 10 MB size cap | `is 10485760` | - |
| B4 | Integrity | MIME allow-list (pdf yes, exe no) | `ANY / NOT ANY` | INV-18 |
| B5 | Security | zero client storage policies (signed-URL only) | `count = 0` | INV-2/22 |

## Council Sign-off

- Architect ✅ — Two-bucket staging→production pattern; quarantine isolated.
- Senior ✅ — Signed-URL auth model mirrors Supabase storage token mechanism.
- QA-Security ✅ — No org_id in path, no client policy, private bucket, MIME whitelist.
- Business ✅ — Enables carrier upload without account creation (adoption).
- Lead Reviewer ✅ — Council-approved plan (Sprint A, this migration).

## Run Command

```bash
make test-db
```
