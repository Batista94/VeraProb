# Test Plan: Legal Gate LGPD (20260922000001) — hardened

## Migration Coverage

| Migration | pgTAP File | Status |
|-----------|-----------|--------|
| `20260922000001_legal_gate_lgpd.sql` | `20260922000001_legal_gate_lgpd_test.sql` | hardened |

## Intent

Prove happy path, adverse, and information-security behaviour for dual LGPD
capture surfaces (Flutter `auth.users` + Telegram `chat_id`). No pass-only
workarounds: every assertion maps to a real failure mode (INV-2/3/22/26, Art. 8).

## Test Scenarios (45 assertions)

| Group | Coverage |
|-------|----------|
| Structure / Seed | tables exist; v1.0 published; sha256 format |
| Security | draft invisible; UPDATE/DELETE blocked; grants; direct INSERT 42501 |
| Happy (Flutter) | pending→accept→current; hash stored; idempotent double-accept; withdraw; re-accept |
| Adverse | missing/draft/closed version rejected (anti-oracle P0002); version bump forces re-consent |
| Isolation | user B cannot SELECT A; accept binds to auth.uid() only |
| Telegram | stale version fails; accept current; binding without consent throws; binding after consent; withdraw unbinds |

## Flutter / Webhook companions

- `test/app/routing/legal_gate_redirect_test.dart` — production `legalGateRedirect` SSOT
- `test/features/shared/legal_consent_screen_test.dart` — happy / adverse / UX-RAW-EXCEPTION
- `test/state/legal_consent_providers_test.dart` — no silent bypass on error
- `telegram_webhook_integration_test.ts` — [I01]/[I01b]/[I01c] version + binding gates

## Run Command

```bash
make test-db
flutter test test/app/routing/legal_gate_redirect_test.dart \
  test/features/shared/legal_consent_screen_test.dart \
  test/state/legal_consent_providers_test.dart -j 1
```
