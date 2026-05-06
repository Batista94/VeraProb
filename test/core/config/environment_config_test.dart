/// Validates the dual-guard on [EnvironmentConfig.skipMfaForSuperAdmin] (INV-6).
///
/// Critical invariant: the bypass MUST only ever evaluate to `true` when BOTH
/// `ENV=dev` AND `--dart-define=SKIP_MFA_DEV=true` are present at compile time.
///
/// `String.fromEnvironment` / `bool.fromEnvironment` are `const` — values are
/// frozen at compile time. Therefore each scenario MUST be executed with the
/// matching `--dart-define` set on the `flutter test` command line. Driver:
///   pwsh scripts/test/run_env_matrix.ps1
///
/// The driver runs this file four times, once per scenario, and asserts that
/// the matching test passes. Tests for non-current scenarios skip themselves.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/core/config/environment.dart';

const _matrixEnv = String.fromEnvironment('ENV', defaultValue: 'dev');
const _matrixSkipFlag = bool.fromEnvironment(
  'SKIP_MFA_DEV',
  defaultValue: false,
);

void main() {
  group('EnvironmentConfig.skipMfaForSuperAdmin (INV-6 dual-guard)', () {
    test('dev + SKIP_MFA_DEV=true → bypass true', () {
      if (_matrixEnv != 'dev' || !_matrixSkipFlag) {
        markTestSkipped(
          'Run with --dart-define=ENV=dev --dart-define=SKIP_MFA_DEV=true',
        );
        return;
      }
      expect(EnvironmentConfig.skipMfaForSuperAdmin, isTrue);
    });

    test('prod + SKIP_MFA_DEV=true → bypass false (CRITICAL)', () {
      if (_matrixEnv != 'prod' || !_matrixSkipFlag) {
        markTestSkipped(
          'Run with --dart-define=ENV=prod --dart-define=SKIP_MFA_DEV=true',
        );
        return;
      }
      expect(
        EnvironmentConfig.skipMfaForSuperAdmin,
        isFalse,
        reason:
            'INV-6 VETO: production must NEVER honor SKIP_MFA_DEV. '
            'isDev guard is the hard gate.',
      );
    });

    test('staging + SKIP_MFA_DEV=true → bypass false', () {
      if (_matrixEnv != 'staging' || !_matrixSkipFlag) {
        markTestSkipped(
          'Run with --dart-define=ENV=staging --dart-define=SKIP_MFA_DEV=true',
        );
        return;
      }
      expect(EnvironmentConfig.skipMfaForSuperAdmin, isFalse);
    });

    test('dev without SKIP_MFA_DEV flag → bypass false', () {
      if (_matrixEnv != 'dev' || _matrixSkipFlag) {
        markTestSkipped(
          'Run with --dart-define=ENV=dev (no SKIP_MFA_DEV flag)',
        );
        return;
      }
      expect(EnvironmentConfig.skipMfaForSuperAdmin, isFalse);
    });
  });
}
