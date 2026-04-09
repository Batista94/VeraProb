# Dart/Flutter Standards

## SOLID & Clean Code (CRITICAL)

- **SRP:** Widgets handle UI only — business logic stays in Riverpod `Notifiers` or `UseCases`
- **DIP:** Every repository MUST have an `abstract class` in `domain/` and implementation in `infrastructure/`
- **Naming:** `PascalCase` classes · `camelCase` methods/vars · `[file]_test.dart` test files
- **Function size:** Max 20 lines per method. Exceed → Extract Method pattern

## DRY vs. AHA (Avoid Hasty Abstractions)

- **Rule of Three:** Only abstract/centralize logic when it repeats in 3+ places
- **Core Location:** Shared logic (Validators, Formatters, Money handling) MUST live in `lib/core/`
- **Source of Truth:** Domain is authoritative. DB constraints (RLS/SQL) synchronize with it — never replace it

## Architectural Data Flow

```
UI → Riverpod Provider → UseCase → Repository Interface → Supabase / External API
```

- **Immutability:** Use `Freezed` for all States and Entities. All class fields `final`
- **Error Handling:** `Result<Failure, Success>` (Either pattern). No `try/catch` in UI. Catch in `Infrastructure`, convert to `Failure`
- **Strong Typing:** `dynamic` is forbidden. Explicit types on all returns and parameters

## Dart Best Practices

- Prefer Mixins or Composition over Inheritance for shared Widget behavior
- Use named parameters for classes with more than 2 fields
- NEVER use `double`/`float` for money — use `Money` VO (BIGINT cents). See INV-2

## Flutter Web Specifics

- Target Flutter Web (>= 3.41.5). WASM compilation is the build target
- Zero use of `dart:html` or `dart:js` — use `dart:js_interop` and `package:web`
- Material 3 design system throughout
- OCC screens: minimize cognitive load, no unnecessary animations or information density
- Widgets must be a11y-compliant (semantic labels, contrast ratios — WCAG 2.2)

## Code Quality Checklist

Before marking any task complete:
- [ ] Widget contains no business logic
- [ ] Repository interface exists in `domain/`, implementation in `infrastructure/`
- [ ] All class fields are `final`
- [ ] No `dynamic` types anywhere
- [ ] No `double`/`float` for currency values
- [ ] Methods are ≤20 lines
- [ ] No `dart:html` or `dart:js` imports

## Testing

- `test/` mirrors `lib/` structure
- Unit tests for all domain logic and UseCases
- Integration tests for Repository implementations — real Supabase, no mocks at infra boundary
- Target: >60% coverage (CI/CD gate) · >80% for core domain/application layers

## PR Scanner Compliance & Forensic Annotation

To pass the `pr_full_scanner.sh` (Lead Reviewer gate), the following rules are non-negotiable:

1. **Physical Metrics (Doubles):** Every `double` declaration that is not for currency (e.g., GPS coordinates, distance, velocity, mass) MUST be annotated with `// Physical Metric - Double Required` on the same line.
   ```dart
   final double latitude; // Physical Metric - Double Required
   final double distanceMeters; // Physical Metric - Double Required
   ```
2. **UTC False Positives:** The scanner flags `DateTime.now()` even in strings. To quote this pattern in descriptions or comments without blocking the commit, use `DateTime . now()` or `DateTime_now`.
3. **Automated Fixes:** If the scanner fails, DO NOT proceed. Add the missing annotations or fix the UTC logic.
