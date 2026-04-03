import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/super_admin/mfa_result_view.dart';

void main() {
  group('MfaVerificationView', () {
    test('MfaVerificationSuccess can be constructed', () {
      const result = MfaVerificationSuccess();
      expect(result, isA<MfaVerificationView>());
    });

    test('MfaVerificationFailure carries failedAttempts and isLockedOut', () {
      const result = MfaVerificationFailure(
        failedAttempts: 3,
        isLockedOut: true,
        message: 'Account locked after 3 failed attempts',
      );
      expect(result.failedAttempts, 3);
      expect(result.isLockedOut, isTrue);
      expect(result.lockedUntil, isNull);
    });

    test('MfaVerificationFailure lockedUntil is optional', () {
      final lockTime = DateTime.utc(2026, 4, 3, 12, 30);
      final result = MfaVerificationFailure(
        failedAttempts: 5,
        isLockedOut: true,
        message: 'Locked',
        lockedUntil: lockTime,
      );
      expect(result.lockedUntil, lockTime);
    });

    test('sealed class exhaustive switch compiles', () {
      const MfaVerificationView view = MfaVerificationSuccess();
      final label = switch (view) {
        MfaVerificationSuccess() => 'ok',
        MfaVerificationFailure() => 'fail',
      };
      expect(label, 'ok');
    });
  });

  group('MfaOperationFailure', () {
    test('implements Exception', () {
      const failure = MfaOperationFailure('MFA service unavailable');
      expect(failure, isA<Exception>());
      expect(failure.message, 'MFA service unavailable');
    });
  });
}
