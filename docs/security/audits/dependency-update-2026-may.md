# Dependency Audit — FULL CONSOLIDATED REPORT

**Date:** 2026-05-07  
**Auditor:** Weslei Batista
**Status:** ALL PHASES COMPLETED  
**Invariants verified:** INV-1, INV-2, INV-6, INV-12, INV-15, INV-22, INV-25, INV-26, INV-33

---

## 1. Executive Summary

This report confirms the total completion of the 4-phase dependency modernization and security audit for project VeraProb. All 3rd-party packages have been vetted for permissive licensing (INV-25), CVE clearance, and architectural alignment (C4).

| Phase | Scope | Status | Date |
|-------|-------|--------|------|
| **1** | Utilities & DevTools | ✓ COMPLETED | 2026-05-07 |
| **2** | Infrastructure & Database | ✓ COMPLETED | 2026-05-07 |
| **3** | UX, Observability & Assets | ✓ COMPLETED | 2026-05-07 |
| **4** | State Engine (Riverpod v3) | ✓ COMPLETED | 2026-05-07 |

---

## 2. Phase 1 & 2: Core & Infrastructure

All packages cleared INV-25 (MIT/BSD/Apache). No critical CVEs found.

| Package | Version (Resolved) | License | Impact |
|---------|-------------------|---------|--------|
| `supabase_flutter` | 2.12.4 | MIT | Full PostgREST v2 compatibility |
| `postgres` | 3.5.9 | BSD-3 | Type-safe binary protocol active |
| `drift` | 2.33.0 | MIT | sqlite3 3.x migration absorbed |
| `timezone` | 0.11.0 | BSD-3 | UTC alias fix applied in `ShiftPattern` |
| `build_runner` | 2.15.0 | BSD-3 | `--delete-conflicting-outputs` now auto-handled |
| `equatable` | 2.0.8 | MIT | Lower-bound security bump |

---

## 3. Phase 3: UX & Observability

Breaking changes in `fl_chart` were refactored in `charts_section.dart`.

| Package | Version (Resolved) | License | Impact |
|---------|-------------------|---------|--------|
| `fl_chart` | 0.70.2 | MIT | Tooltip callback migration complete |
| `google_fonts` | 6.3.3 | BSD-3 | Typography performance optimized |
| `sentry_flutter` | 9.20.0 | MIT | Native stacktrace symbols aligned |
| `posthog_flutter` | 5.24.2 | MIT | Auto-capture privacy filter active |

---

## 4. Phase 4: Riverpod v3 Migration

Major refactor completed. All `StateNotifier` classes migrated to `Notifier` with unified lifecycle management.

* **Changes:** `valueOrNull` replaced by exhaustive pattern matching.
* **Safety:** `ref.mounted` guards added to all async providers.
* **Tests:** 12 new PBT (Glados) tests added to verify state transition invariants.

---

## 5. Final Forensic Validation

### `make full-check` (Final Verdict)

```
Status:  ALL PASS
Total:   6034 tests
Passed:  6011
Skipped: 23 (pre-existing)
Failed:  0
```

### Static Analysis

```
flutter analyze: 0 errors, 0 warnings, 0 hints
dart format: 0 files changed
```

---

## 6. INV-25 Consolidated Sign-Off

> The Engineering Council confirms that the project's dependency graph is clean, fully updated to the latest stable versions compatible with the current Flutter SDK (3.41.5), and compliant with all project security invariants.
>
> All 7 Riverpod breaking changes have been absorbed. Timezone validation is robust. Database schema is in sync with Drift 2.33.0. No `dependency_overrides` or `// ignore` directives remain in the core layers.

**Signature:** Engineering Council — 2026-05-07  
**Branch:** fase10  
**Final Status:** GREEN (Production Ready)
