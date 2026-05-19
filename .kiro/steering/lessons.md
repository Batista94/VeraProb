---
name: lessons
description: Bugs solved + runtime/test/UX heuristics learned during forensic E2E hardening. Steering for all IDE agents (Kiro/Antigravity/Claude).
inclusion: auto
---

# VeraProb — LESSONS LEARNED (Runtime, Test, UX Heuristics)

Bugs forensically dissected during the SuperAdmin E2E hardening cycle. Each rule below is paired with the failure mode it prevents. Cross-references: `CLAUDE.md` Common CI Blocks #5–#10, `.kiro/steering/forensic-standards.md` invariants.

---

## 1. AUTH LIFECYCLE (INV-AUTH-REDIRECT)

**Rule:** Any role-gated guard (`SuperAdminGuard`, RBAC checks, impersonation) MUST be paired with a global `ref.listen<AsyncValue<AuthState>>(authStateProvider, ...)` in `lib/main.dart` that intercepts `AuthChangeEvent.signedOut` and calls `navigatorKey.currentState.pushAndRemoveUntil(LockScreen)`.

**Why:** Without it, `signedOut` flips `isSuperAdmin = false` → guard renders `NotFoundPage` → user is trapped with no path back to login. Confidentiality + UX failure mode.

**How to apply:** When introducing any new guard, grep `lib/main.dart` for the listener. If missing, add it BEFORE merging the guard.

```dart
// lib/main.dart (root ConsumerStatefulWidget):
final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

// MaterialApp:
navigatorKey: _navigatorKey,

// build():
ref.listen<AsyncValue<AuthState>>(authStateProvider, (previous, next) {
  if (previous == null) return;
  if (next.value?.event != AuthChangeEvent.signedOut) return;
  final navigator = _navigatorKey.currentState;
  if (navigator == null) return;
  navigator.pushAndRemoveUntil(
    MaterialPageRoute<void>(builder: (_) => const AdminLockScreen()),
    (_) => false,
  );
});
```

---

## 2. ASYNC CHAIN ISOLATION

**Rule:** Never wrap two independent `await` calls in a single `try/catch` if one failure must NOT discard the other's result. Use per-call `.catchError((_) => fallback)`.

**Why:** Pattern caught: `repo.checkCnpjExists(digits)` + `lookupService.lookup(digits)` shared a unified `try/catch`. ReceitaWS lookup hung → caught error discarded the valid DB duplicate check → user got no feedback. Confidentiality/Integrity failure disguised as UX hiccup.

**How to apply:** Audit every `try/catch` wrapping multiple `await`. Split as below.

```dart
// Wrong — unified catch
try {
  final exists = await repo.checkCnpjExists(digits);
  final lookup = await lookupService.lookup(digits);
  return (exists, lookup);
} catch (_) { return (false, null); }

// Right — independent failure isolation
final exists = await repo.checkCnpjExists(digits).catchError((_) => false);
final lookup = await lookupService.lookup(digits).catchError((_) => null);
return (exists, lookup);
```

---

## 3. NARROW PANEL LAYOUTS

**Rule:** Header `Row(mainAxisAlignment: spaceBetween)` in panels with `maxWidth <= 320px` MUST wrap the title in `Flexible(child: Text(..., overflow: TextOverflow.ellipsis))` and use SHORT action labels (`'Adicionar'`, not `'Adicionar Administrador'`). Preserve full semantic context via `Tooltip(message: 'Full label', child: button)`.

**Why:** TenantUsersTab at `tenant_users_tab.dart:347` overflowed RenderFlex by 140px on a 288px wide constraint. Caught by integration tests as test failures (and visible as yellow/black striping in real builds).

**How to apply:** When designing or modifying any side-drawer/master-detail right-pane header, apply the pattern proactively.

---

## 4. CONSCIOUS BARRIERDISMISSIBLE DECISION

**Rule:** `barrierDismissible: false` is the correct default for destructive operations (Archive, Quota change, Delete) under CIA-Availability — user MUST make a conscious decision. But this changes the navigation contract: any helper that taps NavRail/external widgets through an open modal will silently fail.

**Why:** Test 8.4 (`goToTenantList` mid-modal) hung because the modal barrier ate the NavRail tap. Fix: close modal via `cancelModal(tester)` first.

**How to apply:** Document the `barrierDismissible: false` choice in widget dartdoc. In tests/helpers, require explicit modal close before navigation.

---

## 5. CLEAR ERROR MESSAGING

**Rule:** Never expose debug prefixes (`[DBG 9.6]`, internal IDs, framework stack traces) to end users. Validation messages must be domain-language and actionable.

**Why:** User feedback during 9.6 debug session: *"as mensagens tem que ser claras para os usuarios e nao com numerações e coisas que nao sao claras. UI e UX sao importante."* Engineer-speak shipped to production erodes trust.

**How to apply:** Phrase messages as Portuguese imperative or noun phrases the operator would say aloud: `'Mínimo 10 caracteres.'`, `'CNPJ já cadastrado.'`, `'Motivo obrigatório.'`. Forbidden: `'Validation error: minLength constraint failed'`, `'[DBG ...]'`, raw exception messages.

---

## 6. E2E TEST PROTOCOLS

### 6.1 Dart-Defines Required (E2E-HANG)

**Rule:** ALL `test/integration/e2e/**` invocations MUST pass `--dart-define=SKIP_MFA_DEV=true --dart-define=ENV=dev`. Use `make test-e2e` or `make test-e2e-file FILE=...` — never raw `flutter test` on E2E paths.

**Why:** Without these, `SuperAdminGuard.isAal2 = false` → guard schedules `pushAndRemoveUntil(MfaChallengeScreen)` every frame → `pumpAndSettle` never settles → timeout.

### 6.2 Selectors via Real Widget (E2E-SELECTOR)

**Rule:** Use `find.byKey(ValueKey(...))` or the EXACT widget type (`TextField`, not `TextFormField` if the screen uses `TextField`) and the LITERAL label from source (`'ACESSAR SISTEMA'`, not the inferred `'Entrar'`). Read the screen file before writing selectors.

**Why:** Test 8.5 failed because selector used `TextFormField` while `lock_screen.dart` uses `TextField`. Same with action labels.

### 6.3 No HttpOverrides for Supabase (E2E-HTTPMOCK)

**Rule:** `HttpOverrides.global` does NOT intercept the `HttpClient` already created by `Supabase.initialize()`. To test network failures, demote to repository-level integration test with a fake `SupabaseClient` injected via Riverpod `ProviderScope(overrides: [...])` — NEVER an E2E with `_FailingHttpOverrides`.

**Why:** Test 8.2 architectural dead end — the mock was never invoked. Reframed to test client-side validation as a deterministic error-feedback trigger.

### 6.4 Modal Cancel via Helper

**Rule:** When a modal opens with `barrierDismissible: false`, close it via `cancelModal(tester)` BEFORE attempting any navigation. Tapping NavRail/external widgets through the barrier silently fails.

### 6.5 Test CNPJ Factory

**Rule:** Test-generated CNPJs MUST pass mod-11 check-digit validation. `SuperAdminDataFactory.generateUniqueCnpj()` produces valid digits; random 14-digit strings are rejected by `create_organization_wizard` validator.

---

## 7. REGRESSION ACK DISCIPLINE

**Rule:** Any modification to `lib/domain/**` or `supabase/migrations/**` triggers the scanner's `Regression Alert`. The ONLY acceptable acks are:
1. `// pr_scanner: ignore-regression` comment AFTER Council review documents the diff is intentional and forensically equivalent.
2. Revert the change.

**Why:** Auto-acking without Council review is a process violation. Domain mutations and migration drift are governance-critical.

**How to apply:** Before adding the ignore comment, attach the Council decision record (architect + qa-security + senior sign-off) to the PR description.
