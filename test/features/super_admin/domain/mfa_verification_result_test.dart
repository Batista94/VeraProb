import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/features/super_admin/domain/mfa_verification_result.dart';

void main() {
  group('MfaVerificationResult', () {
    test('MfaVerificationSuccess is a MfaVerificationResult', () {
      const result = MfaVerificationSuccess();
      expect(result, isA<MfaVerificationResult>());
    });

    test('MfaVerificationFailure is a MfaVerificationResult', () {
      const result = MfaVerificationFailure(
        failedAttempts: 3,
        isLockedOut: false,
        message: 'Invalid TOTP code',
      );
      expect(result, isA<MfaVerificationResult>());
    });

    test('pattern matching covers all subtypes', () {
      const MfaVerificationResult success = MfaVerificationSuccess();
      const MfaVerificationResult failure = MfaVerificationFailure(
        failedAttempts: 5,
        isLockedOut: true,
        lockedUntil: null,
        message: 'Account locked',
      );

      final successLabel = switch (success) {
        MfaVerificationSuccess() => 'success',
        MfaVerificationFailure() => 'failure',
      };
      expect(successLabel, 'success');

      final failureLabel = switch (failure) {
        MfaVerificationSuccess() => 'success',
        MfaVerificationFailure() => 'failure',
      };
      expect(failureLabel, 'failure');
    });

    test('MfaVerificationFailure carries lockout details', () {
      final lockedUntil = DateTime.utc(2026, 3, 27, 12, 45);
      final result = MfaVerificationFailure(
        failedAttempts: 5,
        isLockedOut: true,
        lockedUntil: lockedUntil,
        message: 'Conta bloqueada por 15 minutos.',
      );

      expect(result.failedAttempts, 5);
      expect(result.isLockedOut, isTrue);
      expect(result.lockedUntil, lockedUntil);
      expect(result.message, contains('bloqueada'));
    });
  });
}
