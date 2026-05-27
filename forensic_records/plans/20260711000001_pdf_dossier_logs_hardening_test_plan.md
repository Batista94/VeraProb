# Test Plan — 20260711000001_pdf_dossier_logs_hardening

**Migration:** `supabase/migrations/20260711000001_pdf_dossier_logs_hardening.sql`  
**Phase:** 10.4.B Bloco 2 — Hardening  
**Invariants:** INV-3, INV-15, INV-DB

---

## Scope

Enforces append-only semantics and idempotency on `pdf_dossier_logs`.

---

## Test Cases

### H1 — authenticated cannot UPDATE a log entry (INV-3)

```sql
SET LOCAL ROLE test_org_a;
SET LOCAL request.jwt.claim.app_metadata = '{"org_id": "a0000000-0000-0000-0000-00000000000a"}';
-- Insert first
INSERT INTO public.pdf_dossier_logs (...) VALUES (...);
-- Attempt UPDATE → must fail with permission denied
SELECT throws_ok(
  $$ UPDATE public.pdf_dossier_logs SET document_hash_sha256 = 'tampered' WHERE organization_id = '...' $$,
  'permission denied for table pdf_dossier_logs',
  'authenticated role cannot UPDATE forensic log'
);
```

### H2 — authenticated cannot DELETE a log entry (INV-3)

```sql
SELECT throws_ok(
  $$ DELETE FROM public.pdf_dossier_logs WHERE organization_id = '...' $$,
  'permission denied for table pdf_dossier_logs',
  'authenticated role cannot DELETE forensic log'
);
```

### H3 — duplicate (org, entry, hash) rejected (INV-15)

```sql
-- First insert succeeds
INSERT INTO public.pdf_dossier_logs (organization_id, sla_ledger_entry_id, document_hash_sha256, generated_by)
  VALUES ('a0000000-0000-0000-0000-00000000000a', 'e0000000-0000-0000-0000-000000000001', 'hash_abc', 'u0000000-0000-0000-0000-00000000000a');

-- Second identical insert → UNIQUE violation
SELECT throws_ok(
  $$ INSERT INTO public.pdf_dossier_logs (organization_id, sla_ledger_entry_id, document_hash_sha256, generated_by)
     VALUES ('a0000000-0000-0000-0000-00000000000a', 'e0000000-0000-0000-0000-000000000001', 'hash_abc', 'u0000000-0000-0000-0000-00000000000a') $$,
  'duplicate key value violates unique constraint "uq_pdf_dossier_logs_entry_hash"',
  'Duplicate (org, entry, hash) rejected by UNIQUE constraint'
);
```

### H4 — different hash for same entry IS allowed (idempotency safe)

```sql
-- Different hash (different PDF bytes) for same ledger entry → allowed
INSERT INTO public.pdf_dossier_logs (organization_id, sla_ledger_entry_id, document_hash_sha256, generated_by)
  VALUES ('a0000000-0000-0000-0000-00000000000a', 'e0000000-0000-0000-0000-000000000001', 'hash_xyz', 'u0000000-0000-0000-0000-00000000000a');
-- Should succeed (no throws_ok — this must NOT throw)
SELECT pass('Different hash for same entry is allowed');
```

---

## Verification

- `make test-db` — pgTAP must report all cases as PASS.
- Manual: attempt `UPDATE` via Supabase Studio under an authenticated user → expect 403 / permission denied.
- Manual: replay same dossier generation → `ON CONFLICT DO NOTHING` path exercised with no duplicate rows.
