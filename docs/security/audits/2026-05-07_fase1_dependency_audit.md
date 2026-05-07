# Dependency Audit — FASE 1: Utilities & DevTools
**Date:** 2026-05-07  
**Auditor:** Weslei Batista  
**Branch:** fase10  
**Scope:** INV-25 compliance — license verification, CVE check, version governance  

---

## 1. INV-25 License & CVE Clearance

All Phase 1 packages cleared. No critical CVEs found for any package.

| Package | Resolved | License | CVE | Status |
|---------|----------|---------|-----|--------|
| `intl` | 0.20.2 | BSD-3-Clause | none | ✓ APPROVED |
| `equatable` | 2.0.8 | MIT | none | ✓ APPROVED |
| `uuid` | 4.5.3 | MIT | none | ✓ APPROVED |
| `crypto` | 3.0.7 | BSD-3-Clause | none | ✓ APPROVED |
| `cupertino_icons` | 1.0.9 | MIT | none | ✓ APPROVED |
| `test` | 1.30.0 | BSD-3-Clause | none | ✓ APPROVED |
| `build_runner` | 2.15.0 | BSD-3-Clause ¹ | none | ✓ APPROVED |
| `mockito` | 5.6.4 | Apache-2.0 | none | ✓ APPROVED |
| `glados` | 1.1.7 | MIT | none | ✓ APPROVED |
| `mocktail` | 1.0.5 | MIT | none | ✓ APPROVED |
| `flutter_lints` | 6.0.0 | BSD-3-Clause | none | ✓ APPROVED |

¹ pub.dev shows "unknown" label but license text confirmed BSD-3-Clause via `/license` endpoint.

---

## 2. Version Delta

| Package | Previous Constraint | Applied Constraint | Resolved | Note |
|---------|--------------------|--------------------|----------|------|
| `equatable` | `^2.0.5` | `^2.0.8` | 2.0.8 | lower-bound bump |
| `cupertino_icons` | `^1.0.8` | `^1.0.9` | 1.0.9 | lower-bound bump |
| `test` | `^1.25.0` | `^1.30.0` | 1.30.0 | ceiling: Flutter SDK pins test_api=0.7.10; test 1.31.1 requires 0.7.12 ² |
| `build_runner` | `^2.4.0` | `^2.15.0` | 2.15.0 | lower-bound bump |
| `mockito` | `^5.4.4` | `^5.6.4` | 5.6.4 | ceiling: flutter_test pins meta=1.17.0; mockito 5.6.5 requires meta 1.18+ ³ |
| `mocktail` | `^1.0.3` | `^1.0.5` | 1.0.5 | lower-bound bump |

No-change packages (already at latest or constraint covers latest):
`intl` (pinned exact), `uuid`, `crypto`, `glados`, `flutter_lints`

² `test 1.31.1` blocked: requires `test_api 0.7.12`; Flutter SDK (`flutter_test`) pins `test_api` at `0.7.10`.  
³ `mockito 5.6.5` blocked: requires `analyzer ^13.0.0` → `meta ^1.18.0`; Flutter SDK pins `meta` at `1.17.0`.  
Both blockers are Flutter SDK version constraints, not package defects. Unblock via Phase 2 Flutter SDK upgrade.

---

## 3. Build Integrity

### `flutter pub get`
```
Status: SUCCESS
Changed: build_runner 2.13.1 → 2.15.0 (and transitive)
Notable: 48 packages have newer versions incompatible with current constraints (out of Phase 1 scope)
```

### `dart run build_runner build`
```
Status: SUCCESS
Outputs: 2380 generated files
Duration: ~135s
Warning: --delete-conflicting-outputs flag removed in build_runner 2.15.0
         (now handled automatically — no action required)
```

---

## 4. Forensic Validation (Step 0)

### `flutter test`
```
Status:  ALL PASS
Tests:   5148 passed
Skipped: 23 (pre-existing, not related to this change)
Failed:  0
Duration: ~4 minutes
```

### `flutter analyze`
```
Status: PASS
Issues: 0 errors, 0 warnings, 0 hints
```

---

## 5. Out-of-Scope Security Findings

| Finding | Severity | CVE | Affected | Action |
|---------|----------|-----|---------|--------|
| Path traversal in Dart/Flutter SDK | Medium | CVE-2026-27704 | Dart <3.11.0 / Flutter <3.41.0 | Defer to Phase 2 SDK upgrade |

Current `sdk: ^3.10.8` may be in vulnerable range. No exploitable surface identified in VeraProb's runtime profile (server-side rendering only, no user-controlled archive extraction).

---

## 6. INV-25 Sign-Off

> I, Weslei Batista, confirm that all 11 packages in Phase 1 scope carry permissive licenses
> (MIT / BSD-3-Clause / Apache-2.0), have no known critical CVEs at their resolved versions,
> and pass the full VeraProb test suite (5148/5148) with zero lint violations.
>
> Blocked upgrades (test 1.31.1, mockito 5.6.5) are documented with root cause and deferred
> to Phase 2 (Flutter SDK upgrade). No `// ignore` directives added.

**Signature:** Weslei Batista — 2026-05-07  
**Branch:** fase10  
**Invariants verified:** INV-25 (3rd-party free tier + permissive license)
