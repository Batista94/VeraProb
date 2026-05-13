import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/super_admin/mfa_enrollment_result.dart';

void main() {
  group('MfaEnrollmentResult', () {
    test('carries TOTP enrollment fields', () {
      const r = MfaEnrollmentResult(
        factorId: 'f-1',
        totpUri: 'otpauth://totp/VeraProb',
        secret: 'BASE32SECRET',
        recoveryCodes: ['CODE1', 'CODE2'],
      );
      expect(r.factorId, 'f-1');
      expect(r.totpUri, startsWith('otpauth://'));
      expect(r.secret, isNotEmpty);
      expect(r.recoveryCodes, hasLength(2));
    });

    test('recoveryCodes list is never null — One-Time display invariant', () {
      const r = MfaEnrollmentResult(
        factorId: 'f-1',
        totpUri: 'otpauth://totp/VeraProb',
        secret: 'S',
        recoveryCodes: [],
      );
      expect(r.recoveryCodes, isNotNull);
    });
  });
}
