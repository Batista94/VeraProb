# Test Plan: portal_justification_seal (Dispute Portal Refactor — Pacote 1)

## Migration Coverage

| Migration | pgTAP File | Status |
|-----------|-----------|--------|
| `20260818000005_portal_justification_seal.sql` | `20260818000005_portal_justification_seal_test.sql` | ✅ |

## Intent

Makes the carrier's written justification a first-class, sealed part of every
portal counter-evidence submission, and adds the file-optional ("anexo
opcional") contest path so a carrier can dispute with testimony alone.

- `portal_evidence_submissions.justification_text` — NULLABLE at table level
  (legacy rows have none; backfilling fake text would corrupt the forensic
  record). Validity CHECK (`NOT VALID` → `VALIDATE`, zero-downtime) constrains
  only non-null values: `char_length` 10..4000 (Unicode-safe, NOT octet_length)
  and no C0/C1 control chars except TAB/LF/CR. Mandatory-ness for NEW rows is
  enforced in the RPC (including a `trim()` ≥10 check that rejects all-whitespace).
- `dispute_evidence_attachments.sha256_combined_seal` — NULLABLE, format CHECK
  `^[a-f0-9]{64}$`. Computed at finalize as
  `sha256(sha256_server || ':' || justification_text)` (INV-9): testimony sealed
  with the file. Sealed in `prevent_dea_immutable_mutation`.
- `justification_text` added to the sealed-at-ingest block of
  `prevent_pes_immutable_mutation` (re-derived full body).
- `create_portal_submission` — signature changed: old 7-arg overload DROPped,
  new 8-arg `(uuid,text,text,bigint,text,text,text,text)` with required
  `p_justification` (logical position after sha256, before submitter provenance).
  Validation raises the SAME opaque `'Submission rejected.' / insufficient_privilege`
  as every other check (anti-oracle). Stores raw justification; the
  `PORTAL_EVIDENCE_SUBMITTED` ledger fact carries `justification_sha256` (hash,
  not raw text — the ledger is auditable; the testimony stays in the row).
- `register_portal_evidence` — signature UNCHANGED (justification already
  persisted Phase 1). Reads `v_sub.justification_text`, computes the combined
  seal via pgcrypto `encode(extensions.digest(...,'sha256'),'hex')`, stores it on
  the attachment, and adds it to the `PORTAL_EVIDENCE_FINALIZED` ledger fact.

## File-optional design decision (anexo opcional)

`portal_evidence_submissions` requires `file_name` / `mime_type_declared` /
`file_size_bytes_declared` / `sha256_client` to be NOT NULL with format CHECKs.
Forcing NULLs (or fabricated constants) into those columns to record a
testimony-only contest would either fail the constraints or corrupt the forensic
record (a fake file row). Instead the migration adds a NEW minimal append-only
table `portal_justification_submissions` (org-scoped, deny-all RLS,
service_role-only via SECURITY DEFINER RPC, immutability + no-DELETE triggers,
INV-DATA-API-GRANT). It records the testimony + `sha256(justification)` seal and
is born `PENDING_AUDIT` (no quarantine/finalize — there are no bytes to re-hash).
A new ledger type `PORTAL_JUSTIFICATION_SUBMITTED` (chk_ledger_type v6 swap) logs
the fact. New RPC `submit_portal_justification_only(uuid,text)` (service_role)
mints it under the same token idiom (submit-scope, not revoked/expired, queue
disputed, per-token cap counting BOTH file and justification submissions under an
advisory lock). Companion read RPC `list_portal_justification_submissions`
(authenticated TENANT_ADMIN/AUDITOR) surfaces it to the auditor queue — a
separate RPC rather than widening `list_portal_submissions` to avoid PostgREST
signature drift on the existing function.

## Test Scenarios (38 assertions)

| # | Category | Scenario | INV |
|---|----------|----------|-----|
| S1–S2 | Schema | justification_text exists + NULLABLE at table level | INV-3 |
| S3–S4 | Schema | sha256_combined_seal exists + NULLABLE | INV-9 |
| S5–S6 | Schema | portal_justification_submissions exists + RLS enabled | INV-2/22 |
| S7 | Schema | chk_ledger_type admits PORTAL_JUSTIFICATION_SUBMITTED | INV-3 |
| T1 | Adverse | empty justification rejected | INV-26 |
| T2 | Adverse | whitespace-only rejected (trim < 10) | INV-26 |
| T3 | Adverse | 9 chars rejected | INV-26 |
| T4 | Boundary | 10 chars accepted + persisted verbatim | - |
| T5 | Adverse | 4001 chars rejected (cap 4000) | availability |
| T7 | Injection | `<script>` stored raw verbatim | XSS |
| T8 | Injection | `=IMPORTXML` stored raw (export-time prefix) | CSV-injection |
| T9 | Adverse | NUL control char rejected (regex) | INV-26 |
| T10/T10b | Injection | SQLi text is a literal; target table survives | SQLi |
| T14 | Unicode | 4000 multibyte chars accepted (char_length) | INV-26 |
| SEAL1–SEAL3 | Seal | combined seal valid hex, formula-exact, in FINALIZED fact | INV-9 |
| T12/T12b | Immutability | UPDATE justification / combined_seal → restrict_violation | INV-3/9 |
| T15 | Scope | read-scope token rejected on submit | INV-26 |
| T13 | Expiry | expired token rejected | INV-26 |
| T11a/T11b | Cap | per-token submission cap enforced | availability |
| JO1 | File-optional | justification-only born PENDING_AUDIT | - |
| JO2 | File-optional | seal = sha256(justification) | INV-9 |
| JO3 | File-optional | PORTAL_JUSTIFICATION_SUBMITTED fact (pjs_id) | INV-3 |
| JO4 | File-optional | control char rejected (42501) | INV-26 |
| JO5 | File-optional | read-scope token rejected (scope) | INV-26 |
| JO6 | File-optional | record immutable post-ingest | INV-3 |
| L1 | Ledger | submitted fact carries justification_sha256 (not raw) | INV-3 |
| GR1 | Grants | new 8-arg create_portal_submission service_role-only | INV-DATA-API-GRANT |
| GR2 | Grants | submit_portal_justification_only service_role-only | INV-DATA-API-GRANT |
| GR3 | Grants | list_portal_justification_submissions authenticated-only | INV-DATA-API-GRANT |
| GR4 | Grants | old 7-arg create_portal_submission overload dropped | - |

Anti-oracle (per `feedback_anti_oracle_test_assertion`): every rejection asserts
the exact opaque errcode (`42501` for RPC validation, `23001` /
`restrict_violation` for immutability) — never `throwsA(isNot(...))`.

## Updated committed callers (tests ≠ migrations; same package)

- `supabase/tests/20260817000005_portal_submission_rpcs_ledger_test.sql` — all
  `create_portal_submission(...)` calls gain a justification arg; GR1 grant
  string updated to the 8-arg signature.
- `test/integration/portal_evidence_concurrency_test.dart` — both
  `create_portal_submission` RPC calls gain `p_justification`.

## Council Sign-off

- Architect ✅ — Testimony sealed with file (combined seal); file-optional path
  is its own provable artifact, not a polluted file row; agnostic core untouched.
- Senior ✅ — v6 canonical CHECK swap; 7-arg DROP + 8-arg CREATE (PostgREST
  unambiguous); seal via schema-qualified pgcrypto; per-token cap counts both tables.
- QA-Security ✅ — Store-raw + escape-at-export (no seal corruption); anti-oracle
  42501; control-char + length CHECK; immutability covers justification + seal;
  deny-all RLS + explicit grants on the new table.
- Business ✅ — Unlocks testimony-only contests (more disputes resolved without
  evidence friction) while preserving forensic weight.
- Lead Reviewer ✅ — Pending scanner verdict (Pacote 1).

## Run Command

```bash
make test-db
```
