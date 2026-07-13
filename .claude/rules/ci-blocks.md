---
paths:
  - "lib/**/*.dart"
  - "test/**/*.dart"
  - "supabase/migrations/**/*.sql"
---

# VeraProb — Common CI Blocks & Forensic Fixes

Top 20 CI-blocking patterns with fix recipes. Loaded by Claude Code when editing Dart sources or SQL migrations.

---

## 1. INV-DB: Zero-Downtime Migration

**Problem:** Direct `ALTER COLUMN SET NOT NULL`, `DROP COLUMN`, `DROP TABLE`, `DELETE FROM`, or `TRUNCATE` on active tables.

**Fix for `SET NOT NULL` (3-Step Pattern):**

```sql
-- 1. Add CHECK NOT VALID
ALTER TABLE table_name ADD CONSTRAINT col_not_null CHECK (col IS NOT NULL) NOT VALID;
-- 2. Validate (Safe Scan)
ALTER TABLE table_name VALIDATE CONSTRAINT col_not_null;
-- 3. Set NOT NULL with Bypass Comment
ALTER TABLE table_name ALTER COLUMN col SET NOT NULL; -- INV-DB: zero-downtime-verified
```

The comment `-- INV-DB: zero-downtime-verified` MUST be on the same line as the offending DDL.

**Fix for `DROP COLUMN`:** Soft-deprecate (add `_deprecated` suffix, stop writing, migrate reads). Only `DROP COLUMN` after next release cycle with Council approval and bypass comment.

**Fix for `DELETE`/`TRUNCATE`:** Use `deleted_at` soft-delete (INV-7). No hard deletes.

---

## 2. INFRA-LEAK-UI: Infrastructure import in Features layer

**Problem:** `lib/features/` directly imports a concrete `lib/infrastructure/` module (repository or service).

**Fix:** Route through application service or inject via interface.

```dart
// Wrong — features importing infrastructure directly
import 'package:veraprob/infrastructure/sla_audit/justification/file_service/justification_file_service.dart';

// Right — inject interface via Riverpod provider
final service = ref.read(justificationFileServiceProvider);
```

Exception: `infrastructure/observability/` (logger) and `infrastructure/config/` (environment) are permitted cross-cutting concerns.

---

## 3. GENERIC-EXCEPTION-DOMAIN: Generic exception in domain/application

**Problem:** `throw Exception(...)`, `throw StateError(...)`, or `throw FormatException(...)` in domain/application layers.

**Fix:** Use typed domain exception.

```dart
// Wrong
throw StateError('Contract already finalized');
throw FormatException('Invalid UUID: $raw');

// Right
throw IntegrityException('Contract already finalized', field: 'status');
throw IntegrityException('Invalid UUID', field: 'id');
```

Available: `IntegrityException`, `SovereigntyViolationException`, `ConflictException`, `AuthorizationException`, `ResourceNotFoundException`, `IdempotencyProcessingException`.

---

## 4. UTC-BLOCK: `DateTime.now()` without `.toUtc()`

**Problem:** Use of local time instead of universal time.

```dart
// Wrong
final now = DateTime.now();
// Right
final now = DateTime.now().toUtc();
```

In tests, if you need to simulate local time, use `DateTime.now().toUtc().toLocal()` to satisfy the scanner while achieving the offset.

---

## 5. AUTH-TRAP: SignOut leaves user on NotFoundPage

**Problem:** `SuperAdminGuard` (or any role-gated widget) renders `NotFoundPage` on `isSuperAdmin = false`, which becomes true on `signedOut`. User has no path back to login.

**Fix:** Register a global auth listener in `lib/main.dart` that intercepts `signedOut` BEFORE the guard re-renders.

```dart
final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

// MaterialApp:
navigatorKey: _navigatorKey,

// In build():
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

## 6. CATCH-SWALLOW: Unified try/catch discards valid result

**Problem:** Two independent async calls in a single `try/catch`. Failure of the slow/flaky one (e.g., ReceitaWS) discards the successful result of the fast one (e.g., DB duplicate check).

**Fix:** Per-call `.catchError`.

```dart
// Wrong — ReceitaWS hang/throw cancels duplicate check
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

## 7. RENDERFLEX-NARROW: Header overflow in narrow panels

**Problem:** `Row(mainAxisAlignment: spaceBetween)` with long `Text` + long `FilledButton.icon` label inside a panel constrained to `maxWidth: 288px` (or similar narrow detail panel). Throws `RenderFlex overflowed by N pixels`.

**Fix:** Flex the title + shorten action + restore context via Tooltip.

```dart
// Wrong
Row(
  mainAxisAlignment: MainAxisAlignment.spaceBetween,
  children: [
    Text('Administradores'),
    FilledButton.icon(
      onPressed: ...,
      icon: Icon(Icons.add),
      label: Text('Adicionar Administrador'),
    ),
  ],
);

// Right
Row(
  mainAxisAlignment: MainAxisAlignment.spaceBetween,
  children: [
    Flexible(
      child: Text('Administradores', overflow: TextOverflow.ellipsis),
    ),
    Tooltip(
      message: 'Adicionar Administrador',
      child: FilledButton.icon(
        onPressed: ...,
        icon: Icon(Icons.add),
        label: Text('Adicionar'),
      ),
    ),
  ],
);
```

---

## 8. E2E-HANG: pumpAndSettle timeout in superadmin tests

**Problem:** Running `flutter test test/integration/e2e/superadmin/**` without `--dart-define=SKIP_MFA_DEV=true`. `SuperAdminGuard.isAal2 = false` → guard schedules `pushAndRemoveUntil(MfaChallengeScreen)` every frame → `pumpAndSettle` never settles. Also happens when a non-dismissible modal barrier eats taps and blocks the test.

**Fix:** Always use the Makefile target.

```powershell
make test-e2e
# or for a single file:
make test-e2e-file FILE=test/integration/e2e/superadmin/adverse_scenarios_test.dart
```

Test runner scripts and CI workflows for E2E MUST set these flags in env.

**Modal Barrier Check:** If a test opens a dialog/modal with `barrierDismissible: false`, the agent MUST invoke `cancelModal(tester)` to close the dialog before attempting external navigation or tapping other elements. Otherwise, subsequent taps will fail and the test will hang.

---

## 9. E2E-HTTPMOCK: HttpOverrides does not intercept Supabase

**Problem:** Setting `HttpOverrides.global = _FailingHttpOverrides()` to simulate network failure in an E2E test has no effect on the `HttpClient` already created by `Supabase.initialize()` during `app.main()`. The mock is never invoked; real requests succeed (or the test fails for unrelated timing reasons).

**Fix:** Demote network-failure testing to the repository layer with a fake `SupabaseClient` injected via Riverpod override. For E2E, exercise the same code paths via deterministic client-side triggers (validation errors, conflict states) rather than transport faults.

---

## 10. E2E-SELECTOR: Selector mismatch (TextField vs TextFormField, label inference)

**Problem:** Test uses `find.byType(TextFormField)` or `find.widgetWithText(FilledButton, 'Entrar')` while the actual screen uses `TextField` and `'ACESSAR SISTEMA'`. Test finds nothing → timeout.

**Fix:** Open the screen file. Match the literal widget type and literal label. Prefer `ValueKey` selectors over text matching for fields that lack a clear label.

**Linter / Warning Check:** Before finishing any test fix, ensure that no unused imports or variables (common in copied tests) are left in the test file, as this violates strict project linting gates.

```dart
// Wrong
final email = find.byType(TextFormField).first;
final loginBtn = find.widgetWithText(FilledButton, 'Entrar');

// Right
final fields = find.byType(TextField); // matches actual widget
final loginBtn = find.widgetWithText(ElevatedButton, 'ACESSAR SISTEMA');
// or
final email = find.byKey(const ValueKey('admin-lock-email-field'));
```

---

## 11. SECURITY-DEFINER-VIEW: View bypasses RLS (INV-2, INV-22)

**Problem:** `CREATE VIEW` or `CREATE OR REPLACE VIEW` without `WITH (security_invoker = true)`. In Supabase, views default to SECURITY DEFINER — they execute with the view owner's permissions and **bypass RLS on underlying tables**. Any authenticated user querying the view receives all tenants' data unfiltered.

**Fix:** All views in the `public` schema MUST use `WITH (security_invoker = true)`.

```sql
-- Wrong
CREATE OR REPLACE VIEW public.v_something AS
SELECT organization_id, amount_cents FROM public.some_table;

-- Right
CREATE OR REPLACE VIEW public.v_something
  WITH (security_invoker = true)
AS
SELECT organization_id, amount_cents FROM public.some_table;
```

Verify after applying:
```sql
SELECT reloptions FROM pg_class
WHERE relnamespace = 'public'::regnamespace AND relname = 'v_something';
-- Must contain: security_invoker=true
```

> **Note:** `CREATE OR REPLACE VIEW` cannot change the `security_invoker` option on an **existing** view in some PostgreSQL versions. Use `DROP VIEW IF EXISTS` + `CREATE VIEW` to guarantee the option is applied.

---

## 12. PARTITION-RLS-GAP: RLS not inherited by child partitions (INV-2, INV-22)

**Problem:** `ENABLE ROW LEVEL SECURITY` on a parent partitioned table does **NOT** cascade to child partitions created via `CREATE TABLE ... PARTITION OF`. Clients querying a partition directly by name (e.g., `SELECT * FROM public.table_p0`) bypass the parent's RLS entirely — full cross-tenant read/write for any authenticated user.

**Fix:** Every `CREATE TABLE ... PARTITION OF` block MUST be immediately followed by its own RLS + policy block:

```sql
CREATE TABLE public.parent_p0 PARTITION OF public.parent
  FOR VALUES WITH (modulus 4, remainder 0);

-- MANDATORY: mirror parent RLS on every partition
ALTER TABLE public.parent_p0 ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Tenant Isolation: parent_p0" ON public.parent_p0;
CREATE POLICY "Tenant Isolation: parent_p0"
  ON public.parent_p0 FOR ALL
  USING  (organization_id = ((auth.jwt() -> 'app_metadata' ->> 'org_id')::UUID))
  WITH CHECK (organization_id = ((auth.jwt() -> 'app_metadata' ->> 'org_id')::UUID));
```

Repeat for every partition (p0 … pN). Verify all partitions have `rowsecurity = true`:

```sql
SELECT relname, relrowsecurity
FROM pg_class
WHERE relname LIKE 'parent_%'
  AND relnamespace = 'public'::regnamespace
ORDER BY relname;
-- Every row must have relrowsecurity = true
```

---

## 13. INV-DATA-API-GRANT: Missing explicit Data API table grants

**Problem:** Creating a table in schema `public` without explicit `GRANT` statements. In new Supabase projects, tables created in `public` are not exposed to the Data API by default, causing client requests (`supabase-js` or PostgREST) to fail with authorization errors.

**Fix:** Add explicit table-level grants at the end of the migration for the target roles (typically `authenticated` and `service_role`).

```sql
CREATE TABLE public.my_table (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES public.organizations(id)
);

-- Enable RLS
ALTER TABLE public.my_table ENABLE ROW LEVEL SECURITY;

-- MANDATORY: Grant permissions for the Data API
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.my_table TO authenticated;
GRANT ALL ON TABLE public.my_table TO service_role;
```

Do NOT use global `ALTER DEFAULT PRIVILEGES` to restore the insecure legacy defaults, as that violates tenant and data isolation boundaries (INV-22).

---

## 14. LAZY-TEST-BYPASS: Mock/Empty pgTAP Tests

**Problem:** Creating pgTAP tests (`supabase/tests/*.sql`) that only assert `SELECT pass()` or test trivial logic without mocking isolated tenant state and asserting actual table mutations or specific Anti-Oracle errors (42501). This is a severe integrity violation used to bypass CI `test-db` constraints.

**Fix:** pgTAP tests must be authentic and robust.
1. Use `tests.create_org_with_id` or insert isolated `organization_id` data.
2. Insert actual records and simulate the state.
3. Call the target function or RPC.
4. Use `results_eq`, `is()`, or `throws_ok()` with specific expected outputs or Anti-Oracle 42501 errors.

```sql
-- Wrong (Bypass/Lazy)
BEGIN;
SELECT plan(1);
SELECT pass('Bypass test');
SELECT * FROM finish();
ROLLBACK;

-- Right (Authentic Forensic Test)
BEGIN;
SELECT plan(1);
-- ... insert org and setup data ...
SELECT throws_ok(
  $$SELECT public.read_infraction_context('00000000-0000-0000-0000-000000000000'::uuid)$$,
  '42501',
  'Portal access denied.',
  'Missing token returns 42501 (Anti-Oracle)'
);
SELECT * FROM finish();
ROLLBACK;
```

---

## 15. WASM-CONTEXT-LEAK: Stale BuildContext after await

**Problem:** Using `ScaffoldMessenger.of(context)` or `Navigator.of(context)` after an `await` call. In Flutter Web (Wasm), the context may become stale and throw fatal pointer errors. `if (mounted)` does not fully protect against this in Wasm.

**Fix:** Capture the messenger/navigator before the first `await`.

```dart
// Wrong
await repo.save();
if (mounted) ScaffoldMessenger.of(context).showSnackBar(...);

// Right
final messenger = ScaffoldMessenger.of(context);
await repo.save();
messenger.showSnackBar(...);
```

---

## 16. IIFE-UI-SMELL: Immediately Invoked Function Expressions in UI

**Problem:** Using `() { ... }()` inside `build()` or `switch` statements to write block logic inline, or using highly nested ternary operators.

**Fix:** Extract the logic to a private helper method or split the widget.

```dart
// Wrong
switch (asyncValue) {
  AsyncData(:final value) => () {
    final filtered = value.where(...);
    return Column(children: [...]);
  }(),
}

// Right
switch (asyncValue) {
  AsyncData(:final value) => _buildFilteredList(context, value),
}
```

---

## 17. UX-RAW-EXCEPTION: Exposing technical errors to users

**Problem:** Interpolating ANY error object into UI text. Not just `$e` / `e.toString()` — the same leak hides behind state wrappers: `${actionState.error}`, `${asyncValue.error}`, `${snapshot.error}`, `err.toString()`. All of them render raw `PostgrestException`/stack internals to the end user. The static scanner does NOT catch these — this rule is review-enforced; grep for `.error}` and `$e` in any file you touch.

**Fix:** Translate to a human-readable domain message in Portuguese. Do not expose system traces.

```dart
// Wrong
ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
if (actionState.hasError) Text('Erro: ${actionState.error}');
error: (err, st) => Text(err.toString()),

// Right
messenger.showSnackBar(const SnackBar(content: Text('Falha ao processar solicitação. Verifique os dados e tente novamente.')));
if (actionState.hasError) const Text('Falha ao processar a revisão. Tente novamente.');
// Best: omit the custom error builder — AsyncValueWidget's default is already sanitized
// ('Não foi possível carregar os dados. Tente novamente.').
```

---

## 18. ACCENT-FILL-CONTRAST: `Colors.white` on accent fills fails WCAG AA

**Problem:** Setting `Colors.white` as foreground on Indigo Zinc accent fills. White fails 4.5:1 on every accent: `primary #6E7CF6` = 3.6:1, `secondary #5EEAD4` = 1.5:1, `error #EF4444` = 3.8:1. Button labels are 13px — the WCAG "large text" 3:1 allowance does NOT apply.

**Fix:** Foreground on accent fills is always `VeraProbColors.background` (dark). `background` passes on all accents (primary 5.5:1, secondary 13:1, error 5.2:1) and keeps `primary`-as-text on `background` valid (5.5:1). The theme already encodes this (`colorScheme.onPrimary/onSecondary/onError`, `ElevatedButtonTheme`) — never override it back to white at widget level.

```dart
// Wrong
FilledButton.styleFrom(foregroundColor: Colors.white)

// Right — inherit from theme, or if explicit style is required:
FilledButton.styleFrom(foregroundColor: VeraProbColors.background)
```

New color token pairs MUST be validated in both directions (token-as-fill with its foreground, token-as-text on `background`/`surface`) at 4.5:1 text / 3:1 UI glyphs before commit.

---

## 19. GOLDEN-UNWIRED: goldenTest without a generation path

**Problem:** Adding a `goldenTest` to a file that is NOT listed in `scripts/generate_goldens.sh` `TEST_FILES`. The `golden` tag is skipped in `make test` (`dart_test.yaml`), and `make goldens` only runs the hardcoded `TEST_FILES` list — so the baseline PNG is **never generated**. The test is dead weight locally and a guaranteed failure wherever goldens are compared. Same trap: duplicating golden coverage for a widget across two test files (baselines drift; one regen path updates only half).

**Fix:** Goldens for a widget live in ONE dedicated `*_golden_test.dart` file (SSOT), and that file MUST be added to `TEST_FILES` in `scripts/generate_goldens.sh` in the same diff. Behaviour tests stay in the plain `*_test.dart` file with no `goldenTest` calls.

```bash
# scripts/generate_goldens.sh — register the new file or the baseline never exists
TEST_FILES="... \
test/features/admin/presentation/widgets/forensic_log_view_golden_test.dart \
test/features/admin/presentation/widgets/my_new_widget_golden_test.dart"
```

Checklist when adding/moving any `goldenTest`:

1. File name ends in `_golden_test.dart` and contains ONLY goldens.
2. File path present in `generate_goldens.sh` `TEST_FILES`.
3. Test description matches the script's `--name=[Gg]olden` filter (put "Golden" in the group name).
4. Run `make goldens` (hermetic Docker — NEVER `--update-goldens` locally) and commit the PNGs with the test.
5. Grep `goldens/ci/*.png` for orphans (baseline with no referencing test) and delete them.

---

## 20. NUM-CLAMP-DOWNCAST: `num.clamp` result used where `double` expected

**Problem:** `num.clamp(num, num)` returns `num` even when receiver and limits are all `double`. Passing the result to a `double` parameter (`SizedBox(width: ...)`, `EdgeInsets`, etc.) is an implicit downcast — a compile error under Strict Mode (INV-7). Invisible until analyze/compile runs; the code reads correct.

**Fix:** Append `.toDouble()` (or use `clampDouble` from `package:flutter/foundation.dart`).

```dart
// Wrong — masterWidth is num, SizedBox(width:) wants double?
final masterWidth = (totalWidth * 0.35).clamp(minWidth, maxWidth);

// Right
final masterWidth = (totalWidth * 0.35).clamp(minWidth, maxWidth).toDouble();
```

Same family: `num.abs()`, `math.max/min<num>` mixing `int`/`double` args — check the inferred type whenever arithmetic feeds a widget parameter.

---

## 21. ALWAYS-TRUE-RLS-POLICY: PERMISSIVE `USING(true)` on client roles

**Problem:** A PERMISSIVE RLS policy with `USING (true)` or `WITH CHECK (true)` exposed to `public`, `authenticated`, or `anon` is an always-true cross-tenant hole. The PR scanner (`ALWAYS-TRUE-RLS-POLICY-BLOCK`) and standing test `inv22_always_true_policy_invariant_test.sql` block this regression class.

**Fix by table type:**

| Table type | Correct pattern |
|------------|-----------------|
| Tenant-scoped rows | `organization_id::text = auth.jwt() ->> 'organization_id'` (INV-2) |
| Global shared catalog | **Global Catalog RLS Pattern** — `organization_id UUID` nullable; `NULL` = global; policy `organization_id IS NULL OR org match` |
| Internal / service-only | RESTRICTIVE `USING(false)` for `authenticated`; access via `service_role` or SECURITY DEFINER RPC |

SSOT reference migration: `supabase/migrations/20260813000004_dispute_reason_codes.sql`.

```sql
-- Wrong
CREATE POLICY p ON public.my_catalog FOR SELECT TO authenticated USING (true);

-- Wrong (scanner bypass / tautology gaming)
CREATE POLICY p ON public.my_catalog FOR SELECT TO authenticated USING (key IS NOT NULL);

-- Right — Global Catalog RLS Pattern
CREATE TABLE public.my_catalog (
  key TEXT PRIMARY KEY,
  organization_id UUID REFERENCES public.organizations(id),  -- NULL = global
  ...
);
CREATE POLICY my_catalog_select ON public.my_catalog FOR SELECT TO authenticated
  USING (
    organization_id IS NULL
    OR organization_id::text = auth.jwt() ->> 'organization_id'
  );
```

**Prohibited:** `pr_scanner: allow-permissive-true-policy` for editable catalogs (Council bypass is only for irremediable platform tables like `spatial_ref_sys`).

---

## 22. OVER-ENGINEERING: Speculative properties and UI nesting

**Problem:** Bloated models/VOs, redundant mapping layers, misplaced global state, trivial tests, and overly complex layout structures.

**Fix by category:**

* **Model/VO Bloating & Metadata Leak:** Remove backend-only fields (e.g. SHA-256 hashes, raw version numbers, audit timestamps) from Flutter VOs. Keep database-specific tracking in the database.
* **Model/Enum Duplication:** Query the codebase (using grep/search) before writing new domain entities, enums, or models. Re-use or extend existing ones instead of writing duplicates.
* **Pragmatic Mapping Layers:** Do not implement separate DTO-to-Entity mapping layers if the database payload structure and the domain entity are structurally identical and simple.
* **Misplaced Global State (Riverpod):** Keep UI-local states (active tabs, search query input text, drawer toggle states) in widget-local state (`StatefulWidget` or `flutter_hooks`). Restrict Riverpod to shared, async, or database-backed state.
* **Obvious & Trivial Testing:** Avoid writing tests that only assert constructor assignments or stubs. Focus tests on business logic, edge cases, domain exceptions, and state transitions. Use Golden Tests for rendering.
* **Rule of Three (Extracting helpers):** Keep widgets and helper methods inline or feature-scoped unless they are utilized in at least 3 distinct screens/features. Do not pollute `shared/` with premature abstractions.
* **Redundant UI Nesting:** Inline nested layout widgets (e.g. Column-in-Column) and remove single-use helper methods that only wrap a single widget.

```dart
// Wrong — Redundant Column with a single-widget helper
Widget build(BuildContext context) {
  return Column(
    children: [
      _buildHeader(doc),
      Column(
        children: [
          FilledButton(...),
        ]
      )
    ],
  );
}

// Right — Inlined title and simplified layout
Widget build(BuildContext context) {
  return Column(
    children: [
      Text(doc.title),
      FilledButton(...),
    ],
  );
}
```


