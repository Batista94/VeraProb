# Test Import Convention

## Rule: Absolute imports only

All test files MUST import production code exclusively via package imports:

```dart
import 'package:veraprob/domain/shared/money.dart';
```

Shared test doubles (fakes, stubs) live in `lib/testing/` and are also imported via package:

```dart
import 'package:veraprob/testing/fakes/fake_date_time_provider.dart';
import 'package:veraprob/testing/fakes/fake_uuid_generator.dart';
```

## Permitted exception: dart:io helpers

Two test infrastructure files use `dart:io` (`Platform`, `File`) and **cannot** be
placed in `lib/` without breaking the WASM/web build:

- `test/infrastructure/postgres/postgres_test_config.dart`
- `test/integration/e2e/helpers/superadmin_*.dart`

Files in `test/infrastructure/`, `test/integration/`, and `test/e2e/` that import
these config helpers MAY use relative imports pointing to these specific files.
No other relative imports are permitted.

## Rule: _test.dart suffix

Every test runner file (contains `void main()` / `group()` / `test()`) MUST end
with `_test.dart`.

Utilities (mocks, fakes, helpers, fixtures) must NOT end with `_test.dart`.
Place them in folders named `mocks/` or `helpers/`.

## Rule: Unit test isolation

Tests in `test/domain/` and `test/application/` (excluding `test/application/adapters/`)
must NOT import supabase, http, postgres, or any network package.
Use fakes from `lib/testing/fakes/` instead.
