# Test Plan: read_infraction_context RPC

## Migration Coverage

| Migration | pgTAP File | Status |
|-----------|-----------|--------|
| `20260819000003_read_infraction_context_rpc.sql` | `20260819000003_read_infraction_context_test.sql` | ✅ |

## Intent

The dispute portal page called `Future.wait([readDispute, readInfractionContext])`.
`read_infraction_context` did not exist in any migration → PGRST202 → the bare
`catch(_)` in `supabase_portal_dispute_gateway.dart` rewrote the error to "Link
inválido ou expirado", and every failed load consumed one `access_count` slot (token
burn). Tokens exhausted after 5 page-open attempts.

Fix: create the missing RPC.

Security model rationale (QA-Security explicit ratification):
- SECURITY DEFINER: anon callers have no JWT org claim (mirrors `read_dispute_portal`).
- Advisory lock on token hash: normalises timing for FOUND / NOT FOUND paths to
  prevent measurable side-channel distinguishing valid from invalid tokens.
- Single opaque `insufficient_privilege` (42501) for ALL invalid paths: expired /
  revoked / exhausted / not-found / internal error. `EXCEPTION WHEN OTHERS` re-raises
  as 42501 so unforeseen errors never leak stack information.
- NO `access_count` increment, NO ledger append: `read_dispute_portal` already tracks
  each access; double-side-effects re-introduce the token burn bug.
- Projection disclosure: `penalty_value_cents` + org identity (name / CNPJ / logo_url)
  are disclosed to a tokened anon. This is the designed contract for the
  `InfractionContextProjection` Dart model and the `dispute_context_card` widget
  (existing code). The disclosure is scoped to: (a) a valid, non-expired, non-revoked,
  non-exhausted token, (b) bound to the caller's own infraction. No new surface.
- `service_role` intentionally excluded (REVOKE FROM PUBLIC strips it; not re-granted
  — external carrier-facing function, not a backend tool).

## Test Scenarios

| # | Category | Scenario | INV |
|---|----------|----------|-----|
| T1 | Schema | `read_infraction_context(uuid)` function exists | — |
| T2 | Security | `read_infraction_context` is SECURITY DEFINER | INV-22 |
| T3 | Grant | `anon` may EXECUTE | INV-26 |
| T4 | Grant | `authenticated` may EXECUTE | INV-26 |
| T5 | Grant | `service_role` may NOT EXECUTE | INV-22 |
| T6 | Functional | Valid token → non-NULL JSONB projection | — |
| T7 | Projection | `asset_identifier` = `vehicle_plate` from queue row | INV-1 |
| T8 | Projection | `penalty_value_cents` = `fine_cents` from `verdict_evidence` | INV-4 |
| T9 | No burn | `access_count` unchanged after call (no token burn) | INV-3 |
| T10 | Anti-oracle | Expired token → opaque 42501 | INV-26 |
| T11 | Anti-oracle | Revoked token → opaque 42501 | INV-26 |
| T12 | Anti-oracle | Exhausted token → opaque 42501 | INV-26 |
| T13 | Anti-oracle | Unknown token → opaque 42501 | INV-26 |

## Council Sign-off

- **Architect:** token-scoped SECURITY DEFINER pattern mirrors read_dispute_portal ✅
- **QA/Security:** carrier disclosure ratification; advisory lock; EXCEPTION WHEN OTHERS guard ✅
- **Senior:** no-burn guarantee; location_label derivation; COALESCE on logo_url ✅
- **Lead Reviewer:** pr_scanner ignore-regression comment in migration header ✅
