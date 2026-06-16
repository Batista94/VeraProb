# Test Plan: approve_sanction reason code + reviewer note

## Migration Coverage

| Migration | pgTAP File | Status |
|-----------|-----------|--------|
| `20260818000006_approve_sanction_reason_code.sql` | `20260818000006_approve_sanction_reason_code_test.sql` | ✅ |

## Intent

Stop discarding the auditor's verdict rationale. The `SentencePanelModal`
collected a taxonomy reason code (+ optional free-text note) when sealing a
pending verdict ("CONFIRMAR INFRAÇÃO"), but `approve_sanction` had no parameter
to carry it — so it was dropped at the `_onApprove` boundary. This threads both
into the canonical `VERDICT_SEALED` ledger fact (INV-21 / INV-23 explainability).

- Signature: 5-arg overload DROPped, recreated 7-arg
  `(uuid,uuid,uuid,text,timestamptz,text,text)` with trailing `p_reason_code`
  + `p_reviewer_reason` `DEFAULT NULL`. Existing 5-arg callers / committed pgTAP
  keep resolving (defaults fill the gap; body no-ops on NULL).
- `reason_code` OPTIONAL for approval (sealing affirms the engine's verdict) but
  VALIDATED against the closed `dispute_reason_codes` taxonomy when supplied;
  unknown/inactive code → opaque `insufficient_privilege` (anti-oracle, INV-26).
- `reviewer_reason` stored raw in the ledger fact (escape only at render/export).
- Grants mirror the original posture exactly: `authenticated` only; `anon` +
  `service_role` denied.

## Test Scenarios

| # | Category | Scenario | INV |
|---|----------|----------|-----|
| S1 | Schema | `approve_sanction` exists with the 7-arg signature | - |
| S2 | Schema | `approve_sanction` is SECURITY DEFINER | INV-2 |
| GR1 | Grants | `authenticated` may EXECUTE the 7-arg overload | INV-DATA-API-GRANT |
| GR2 | Grants | `anon` may NOT EXECUTE | INV-22 |
| GR3 | Grants | `service_role` may NOT EXECUTE | INV-22 |
| GR4 | Grants | old 5-arg overload no longer exists | - |
| A1 | Happy | seal with a valid code → `applied` + one `VERDICT_SEALED` | INV-3 |
| A2 | Persistence | ledger payload `reason_code` == supplied code | INV-21/23 |
| A3 | Persistence | ledger payload `reviewer_reason` == supplied note (raw) | INV-23 |
| A4 | Back-compat | 5-arg-style call (NULL code) still seals; payload code NULL | - |
| T1 | Adverse | unknown/inactive code → `insufficient_privilege` (no seal) | INV-26 |
| T2 | Injection | SQLi text in `p_reviewer_reason` stored as a literal | SQLi |
| T3 | Concurrency | second concurrent approve → `IdempotencyProcessingException` | INV-3 |

Anti-oracle (per `feedback_anti_oracle_test_assertion`): the unknown-code
rejection asserts the exact opaque `insufficient_privilege` errcode — never a
negative `isNot(...)` match.

## Updated committed callers (tests ≠ migrations; same package)

- `supabase/tests/20260812000001_approve_reject_sanction_rpc_test.sql` — the
  `has_function` signature assertion and the three `has_function_privilege`
  grant-string assertions for `approve_sanction` updated from the 5-arg to the
  7-arg signature (the function arity changed). Positional/named call-sites are
  unaffected (defaults).

## Council Sign-off

- Architect ✅ — additive optional params; agnostic core untouched; verdict
  rationale belongs in the append-only ledger fact, not a new queue column.
- Senior ✅ — 5-arg DROP + 7-arg CREATE (PostgREST unambiguous; single overload);
  defaults preserve back-compat; in-memory backend mirrored for parity.
- QA-Security ✅ — code validated zero-trust + anti-oracle opaque; store-raw note;
  grant posture unchanged (authenticated-only); JWT sub/org/role re-asserted.
- Lead Reviewer ⏳ — pending scanner verdict.

## Run Command

```bash
make test-db
```
