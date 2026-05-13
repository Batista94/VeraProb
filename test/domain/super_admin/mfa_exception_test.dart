import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/super_admin/mfa_exception.dart';

void main() {
  group('MfaException', () {
    test('base: message, optional code, isNotEnabled defaults to false', () {
      const ex = MfaException('Error', code: 'err_code');
      expect(ex.message, 'Error');
      expect(ex.code, 'err_code');
      expect(ex.isNotEnabled, isFalse);
      expect(ex.toString(), 'Error');
    });

    test('isNotEnabled=true for MFA-disabled environments', () {
      const ex = MfaException('MFA disabled', isNotEnabled: true);
      expect(ex.isNotEnabled, isTrue);
    });
  });

  group('[CIA:C] CodeExpiredException', () {
    test('is subtype of MfaException', () {
      const ex = CodeExpiredException();
      expect(ex, isA<MfaException>());
    });

    test('code is totp_expired', () {
      expect(const CodeExpiredException().code, 'totp_expired');
    });

    test('message is non-empty', () {
      expect(const CodeExpiredException().message, isNotEmpty);
    });
  });

  group('[CIA:C] InvalidMfaCodeException', () {
    test('carries the invalid input for forensic log', () {
      const ex = InvalidMfaCodeException("' OR 1=1");
      expect(ex.invalidInput, "' OR 1=1");
    });

    test('code is invalid_mfa_code', () {
      expect(const InvalidMfaCodeException('').code, 'invalid_mfa_code');
    });
  });

  group('[CIA:I] CodeAlreadyUsedException', () {
    test('code is code_already_used', () {
      expect(const CodeAlreadyUsedException().code, 'code_already_used');
    });
  });

  group('[CIA:A] MfaLockoutException', () {
    test('carries failedAttempts', () {
      const ex = MfaLockoutException(failedAttempts: 5);
      expect(ex.failedAttempts, 5);
    });

    test('lockedUntil must be UTC when set', () {
      final ts = DateTime.utc(2026, 5, 6, 22, 0);
      final ex = MfaLockoutException(failedAttempts: 5, lockedUntil: ts);
      expect(ex.lockedUntil!.isUtc, isTrue);
    });
  });
}
