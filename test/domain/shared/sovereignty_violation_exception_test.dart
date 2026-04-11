import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/shared/sovereignty_violation_exception.dart';

void main() {
  group('SovereigntyViolationException', () {
    test('creates with required org IDs and default message', () {
      const exception = SovereigntyViolationException(
        payloadOrgId: 'org-aaa',
        jwtOrgId: 'org-bbb',
      );

      expect(exception.payloadOrgId, 'org-aaa');
      expect(exception.jwtOrgId, 'org-bbb');
      expect(exception.message, 'Tenant isolation violation.');
    });

    test('creates with custom forensic message', () {
      const exception = SovereigntyViolationException(
        payloadOrgId: 'org-attacker',
        jwtOrgId: 'org-victim',
        message: 'Spoofed organization claim detected.',
      );

      expect(exception.message, 'Spoofed organization claim detected.');
      expect(exception.payloadOrgId, 'org-attacker');
      expect(exception.jwtOrgId, 'org-victim');
    });

    test('toString is sanitized — NO forensic org IDs for generic loggers', () {
      const exception = SovereigntyViolationException(
        payloadOrgId: 'org-attacker',
        jwtOrgId: 'org-victim',
      );

      final str = exception.toString();

      // Sanitized: only the message, no IDs
      expect(str, contains('SovereigntyViolationException'));
      expect(str, contains('Tenant isolation violation.'));
      expect(str, isNot(contains('org-attacker')));
      expect(str, isNot(contains('org-victim')));
    });

    test('toForensicString includes org IDs for internal security logging', () {
      const exception = SovereigntyViolationException(
        payloadOrgId: 'org-attacker-123',
        jwtOrgId: 'org-victim-456',
      );

      final forensic = exception.toForensicString();

      expect(forensic, contains('SovereigntyViolationException'));
      expect(forensic, contains('org-attacker-123'));
      expect(forensic, contains('org-victim-456'));
    });

    test('toForensicString uses custom message when provided', () {
      const exception = SovereigntyViolationException(
        payloadOrgId: 'org-x',
        jwtOrgId: 'org-y',
        message: 'Custom forensic message',
      );

      final forensic = exception.toForensicString();
      expect(forensic, contains('Custom forensic message'));
      expect(forensic, contains('org-x'));
      expect(forensic, contains('org-y'));
    });

    test('equality is based on all fields', () {
      const ex1 = SovereigntyViolationException(
        payloadOrgId: 'org-a',
        jwtOrgId: 'org-b',
        message: 'msg',
      );
      const ex2 = SovereigntyViolationException(
        payloadOrgId: 'org-a',
        jwtOrgId: 'org-b',
        message: 'msg',
      );
      const ex3 = SovereigntyViolationException(
        payloadOrgId: 'org-different',
        jwtOrgId: 'org-b',
        message: 'msg',
      );

      expect(ex1, equals(ex2));
      expect(ex1, isNot(equals(ex3)));
    });

    test('hashCode is consistent with equality', () {
      const ex1 = SovereigntyViolationException(
        payloadOrgId: 'org-a',
        jwtOrgId: 'org-b',
        message: 'msg',
      );
      const ex2 = SovereigntyViolationException(
        payloadOrgId: 'org-a',
        jwtOrgId: 'org-b',
        message: 'msg',
      );

      expect(ex1.hashCode, equals(ex2.hashCode));
    });

    test('implements Exception', () {
      const exception = SovereigntyViolationException(
        payloadOrgId: 'org-a',
        jwtOrgId: 'org-b',
      );

      expect(exception, isA<Exception>());
    });
  });
}
