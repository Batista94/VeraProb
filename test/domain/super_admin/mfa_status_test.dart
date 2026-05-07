import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/features/super_admin/domain/mfa_status.dart';

void main() {
  group('MfaStatus', () {
    group('needsEnrollment', () {
      test('returns true when no factor is enrolled', () {
        const status = MfaStatus(
          currentLevel: MfaAssuranceLevel.aal1,
          hasEnrolledFactor: false,
        );
        expect(status.needsEnrollment, isTrue);
        expect(status.needsChallenge, isFalse);
        expect(status.isFullyAuthenticated, isFalse);
      });

      test('returns false when factor is enrolled', () {
        const status = MfaStatus(
          currentLevel: MfaAssuranceLevel.aal1,
          hasEnrolledFactor: true,
          factorId: 'factor-123',
        );
        expect(status.needsEnrollment, isFalse);
      });
    });

    group('needsChallenge', () {
      test('returns true when enrolled but AAL1', () {
        const status = MfaStatus(
          currentLevel: MfaAssuranceLevel.aal1,
          hasEnrolledFactor: true,
          factorId: 'factor-123',
        );
        expect(status.needsChallenge, isTrue);
        expect(status.needsEnrollment, isFalse);
        expect(status.isFullyAuthenticated, isFalse);
      });

      test('returns false when AAL2', () {
        const status = MfaStatus(
          currentLevel: MfaAssuranceLevel.aal2,
          hasEnrolledFactor: true,
          factorId: 'factor-123',
        );
        expect(status.needsChallenge, isFalse);
      });

      test('returns false when not enrolled', () {
        const status = MfaStatus(
          currentLevel: MfaAssuranceLevel.aal1,
          hasEnrolledFactor: false,
        );
        expect(status.needsChallenge, isFalse);
      });
    });

    group('isFullyAuthenticated', () {
      test('returns true when enrolled and AAL2', () {
        const status = MfaStatus(
          currentLevel: MfaAssuranceLevel.aal2,
          hasEnrolledFactor: true,
          factorId: 'factor-123',
        );
        expect(status.isFullyAuthenticated, isTrue);
        expect(status.needsEnrollment, isFalse);
        expect(status.needsChallenge, isFalse);
      });

      test('returns false when AAL2 but not enrolled (edge case)', () {
        const status = MfaStatus(
          currentLevel: MfaAssuranceLevel.aal2,
          hasEnrolledFactor: false,
        );
        expect(status.isFullyAuthenticated, isFalse);
      });
    });

    group('lockout state', () {
      test('carries lockout information', () {
        final lockedUntil = DateTime.utc(2026, 3, 27, 12, 30);
        final status = MfaStatus(
          currentLevel: MfaAssuranceLevel.aal1,
          hasEnrolledFactor: true,
          factorId: 'factor-123',
          isLockedOut: true,
          failedAttempts: 5,
          lockedUntil: lockedUntil,
        );
        expect(status.isLockedOut, isTrue);
        expect(status.failedAttempts, 5);
        expect(status.lockedUntil, lockedUntil);
      });
    });

    group('equality', () {
      test('equal when all fields match', () {
        const a = MfaStatus(
          currentLevel: MfaAssuranceLevel.aal1,
          hasEnrolledFactor: true,
          factorId: 'f1',
        );
        const b = MfaStatus(
          currentLevel: MfaAssuranceLevel.aal1,
          hasEnrolledFactor: true,
          factorId: 'f1',
        );
        expect(a, equals(b));
        expect(a.hashCode, b.hashCode);
      });

      test('not equal when fields differ', () {
        const a = MfaStatus(
          currentLevel: MfaAssuranceLevel.aal1,
          hasEnrolledFactor: true,
        );
        const b = MfaStatus(
          currentLevel: MfaAssuranceLevel.aal2,
          hasEnrolledFactor: true,
        );
        expect(a, isNot(equals(b)));
      });
    });
  });
}
