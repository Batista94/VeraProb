# Test Plan: portal_rpc_observability (Dispute Portal Submission — PKG1)

## Migration Coverage

| Migration | pgTAP File | Status |
|-----------|-----------|--------|
| `20260825000001_portal_rpc_observability.sql` | `20260825000001_portal_rpc_observability_test.sql` | ✅ |

## Intent

Restores server-side observability to the dispute portal submission esteira
without weakening the carrier-facing Anti-Oracle (INV-26). Two changes, both to
SECURITY DEFINER service_role-only RPCs, rebuilt verbatim from the latest
`20260818000005` bodies and patched:

- **A — DETAIL tokens.** Every `RAISE EXCEPTION 'Submission rejected.'` in
  `create_portal_submission` and `submit_portal_justification_only` keeps its
  opaque message and `insufficient_privilege` (42501) ERRCODE but gains
  `DETAIL = 'PORTAL_SUBMIT_REJECTED:<CODE>'`. PostgREST strips DETAIL for 42501
  from the HTTP body, so the anonymous carrier still receives a byte-identical
  404 from the edge function; the machine code reaches ONLY the service_role
  edge function via `error.details` (Sentry triage). Codes: `MIME_UNSUPPORTED`,
  `FILE_SIZE_OUT_OF_RANGE`, `SHA256_INVALID`, `JUSTIFICATION_INVALID`,
  `TOKEN_SOVEREIGNTY`, `QUEUE_STATE_INVALID`, `SUBMISSION_CAP_EXCEEDED`.

- **B — QUARANTINE hash idempotency** in `create_portal_submission`, keyed on
  `(token_id, sha256_client)` over non-deleted rows whose status is `QUARANTINE`.
  A retry of the SAME bytes whose prior row is still `QUARANTINE` (the
  network-failure-between-create-and-upload case) reuses that row +
  `quarantine_storage_path` instead of consuming a `max_submissions` slot — the
  transient-failure permanent-block bug. The lookup runs AFTER token + queue
  validation, so a revoked / expired / wrong-scope token still fails opaquely even
  when the sha matches (INV-18 Zero-Trust — Veto 1).

  Design note (discovered in testing): `register_portal_evidence` and
  `submit_portal_justification_only` (20260820000002) REVOKE the token on a
  successful finalize, so a row that reached `PENDING_AUDIT` is unreachable via the
  same token (`TOKEN_SOVEREIGNTY` guards it) — the originally-planned
  `already_finalized` / `signedUrl`-omission branch was dead code and was dropped.
  Only `QUARANTINE` rows are reused; any OTHER prior state (e.g. a `MISMATCH` whose
  token is still live) falls through to a FRESH submission with a FRESH quarantine
  path, so a sealed file is NEVER re-signed (INV-9 — Veto 2 satisfied structurally).

`create_portal_submission` return shape is UNCHANGED (2 columns) → `CREATE OR
REPLACE` (no `DROP`, no type regen). `submit_portal_justification_only` is rebuilt
from its TRUE latest definition (20260820000002 — preserving the
queue→`pending_peer_review` advance and one-shot token revocation; basing it on
818 would have regressed both). The 8-arg INPUT signature is unchanged: PostgREST
resolution and the committed grant assertions in `20260817000005_*` /
`20260818000005_*` stay green. Grants re-asserted defensively (service_role-only).

## Anti-Oracle preservation (INV-26)

The carrier never sees DETAIL: the edge function discards the entire PostgREST
error on any non-200 and returns the canonical 404. Existing committed pgTAP
`throws_ok(..., '42501', NULL, ...)` assertions pass `NULL` for the message and
do not inspect DETAIL, so they remain valid unchanged — proof there is no
stale-test breakage from this migration.

## Test Scenarios (new pgTAP file)

| ID | Scenario | Assertion |
|----|----------|-----------|
| IDEMP1 | 1st submit (QUARANTINE) then 2nd submit SAME (token, sha) | same `submission_id`; same `quarantine_path` (no re-mint); exactly ONE `portal_evidence_submissions` row for the token |
| IDEMP2 | cap NOT consumed by the retry | with `max_submissions = 1`, a 1st submit + an identical-sha retry both succeed (retry deduped); a DIFFERENT-sha submit then raises `42501` (cap genuinely enforced on new bytes) |
| VETO1 | revoked token on the idempotency path (matching prior sha) | raises `42501` (token validated before dedup, INV-18) |
| DET-* | each validation path | `DO $$ … GET STACKED DIAGNOSTICS d = PG_EXCEPTION_DETAIL $$` equals `PORTAL_SUBMIT_REJECTED:<CODE>` for MIME / SIZE / SHA / JUSTIFICATION / TOKEN / QUEUE / CAP |
| JO-DET | `submit_portal_justification_only` invalid justification | DETAIL equals `PORTAL_SUBMIT_REJECTED:JUSTIFICATION_INVALID` |
| GR1 | grant parity | `create_portal_submission(uuid,text,text,bigint,text,text,text,text)` is service_role-only (authenticated/anon denied) — matches committed assertions |

## Edge / Dart coverage (companion, not pgTAP)

- deno `supabase/functions/tests/portal_submit_request_unit_test.ts`: RPC error
  with `details`/`code` → still 404 + detail logged; `already_finalized:true` →
  200 omitting `signedUrl`; storage `signErr` → **503** (opaque body), not 404;
  80ms floor holds.
- Dart `test/integration/portal_evidence_concurrency_test.dart`: AT-06 reworked
  to DISTINCT sha per client (cap race still meaningful post-idempotency); new
  AT-07 — 2 parallel SAME-(token,sha) submits → ONE row, same `submission_id`.

## Invariants

INV-3 (no duplicate ledger fact on retry), INV-9 (never re-sign a sealed file),
INV-18 (token validated before idempotency early-return), INV-22 (lookup scoped
through `token_id` → org), INV-26 (DETAIL invisible to carrier),
INV-DATA-API-GRANT (explicit re-grant).
