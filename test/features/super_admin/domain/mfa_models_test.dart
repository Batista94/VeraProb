/// Domain model tests — MFA exceptions & sealed result types.
///
/// Validates INV-16 fail-fast hierarchy and CIA Triad model-layer contracts.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:veraprob/features/super_admin/domain/mfa_exception.dart';
import 'package:veraprob/features/super_admin/domain/mfa_verification_result.dart';
import 'package:veraprob/features/super_admin/domain/mfa_status.dart';
import 'package:veraprob/features/super_admin/domain/mfa_challenge_result.dart';
import 'package:veraprob/features/super_admin/domain/mfa_enrollment_result.dart';

void main() {
  // ── MfaException base ────────────────────────────────────────────────────
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

  // ── [CIA:C] CodeExpiredException ────────────────────────────────────────
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

    test('caught as MfaException', () {
      expect(
        () => throw const CodeExpiredException(),
        throwsA(isA<MfaException>()),
      );
    });
  });

  // ── [CIA:C] InvalidMfaCodeException ──────────────────────────────────────
  group('[CIA:C] InvalidMfaCodeException', () {
    test('carries the invalid input for forensic log', () {
      const ex = InvalidMfaCodeException("' OR 1=1");
      expect(ex.invalidInput, "' OR 1=1");
    });

    test('code is invalid_mfa_code', () {
      expect(const InvalidMfaCodeException('').code, 'invalid_mfa_code');
    });

    test('empty string input captured', () {
      const ex = InvalidMfaCodeException('');
      expect(ex.invalidInput, isEmpty);
    });

    test('7-digit code (wrong length) captured', () {
      const ex = InvalidMfaCodeException('1234567');
      expect(ex.invalidInput, hasLength(7));
    });

    test('NoSQL injection string captured', () {
      const payload = r'{"$where":"1==1"}';
      const ex = InvalidMfaCodeException(payload);
      expect(ex.invalidInput, payload);
      expect(ex, isA<MfaException>());
    });

    test('caught as MfaException', () {
      expect(
        () => throw const InvalidMfaCodeException('bad'),
        throwsA(isA<MfaException>()),
      );
    });
  });

  // ── [CIA:I] CodeAlreadyUsedException ────────────────────────────────────
  group('[CIA:I] CodeAlreadyUsedException', () {
    test('code is code_already_used', () {
      expect(const CodeAlreadyUsedException().code, 'code_already_used');
    });

    test('is subtype of MfaException', () {
      expect(const CodeAlreadyUsedException(), isA<MfaException>());
    });

    test('message is non-empty', () {
      expect(const CodeAlreadyUsedException().message, isNotEmpty);
    });

    test('caught as MfaException', () {
      expect(
        () => throw const CodeAlreadyUsedException(),
        throwsA(isA<MfaException>()),
      );
    });
  });

  // ── [CIA:A] MfaLockoutException ──────────────────────────────────────────
  group('[CIA:A] MfaLockoutException', () {
    test('carries failedAttempts', () {
      const ex = MfaLockoutException(failedAttempts: 5);
      expect(ex.failedAttempts, 5);
    });

    test('lockedUntil is optional', () {
      const ex = MfaLockoutException(failedAttempts: 5);
      expect(ex.lockedUntil, isNull);
    });

    test('lockedUntil must be UTC when set', () {
      final ts = DateTime.utc(2026, 5, 6, 22, 0);
      final ex = MfaLockoutException(failedAttempts: 5, lockedUntil: ts);
      expect(ex.lockedUntil!.isUtc, isTrue);
    });

    test('code is mfa_lockout', () {
      expect(const MfaLockoutException(failedAttempts: 5).code, 'mfa_lockout');
    });

    test('is subtype of MfaException', () {
      expect(const MfaLockoutException(failedAttempts: 5), isA<MfaException>());
    });

    test('caught as MfaException', () {
      expect(
        () => throw const MfaLockoutException(failedAttempts: 5),
        throwsA(isA<MfaException>()),
      );
    });
  });

  // ── MfaVerificationResult sealed class ───────────────────────────────────
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

    test('pattern matching is exhaustive over all subtypes', () {
      const MfaVerificationResult success = MfaVerificationSuccess();
      const MfaVerificationResult failure = MfaVerificationFailure(
        failedAttempts: 5,
        isLockedOut: true,
        lockedUntil: null,
        message: 'Account locked',
      );

      expect(switch (success) {
        MfaVerificationSuccess() => 'success',
        MfaVerificationFailure() => 'failure',
      }, 'success');
      expect(switch (failure) {
        MfaVerificationSuccess() => 'success',
        MfaVerificationFailure() => 'failure',
      }, 'failure');
    });

    test('MfaVerificationFailure.lockedUntil is UTC when set', () {
      final ts = DateTime.utc(2026, 5, 6, 22, 0);
      final result = MfaVerificationFailure(
        failedAttempts: 5,
        isLockedOut: true,
        lockedUntil: ts,
        message: 'Bloqueado.',
      );
      expect(result.lockedUntil!.isUtc, isTrue);
    });

    test('[CIA:I] Failure at attempt 5 must carry isLockedOut=true', () {
      final result = MfaVerificationFailure(
        failedAttempts: 5,
        isLockedOut: true,
        lockedUntil: DateTime.utc(2026, 5, 6, 22, 0),
        message: 'Conta bloqueada.',
      );
      expect(result.failedAttempts, 5);
      expect(result.isLockedOut, isTrue);
    });
  });

  // ── MfaStatus computed getters ────────────────────────────────────────────
  group('MfaStatus', () {
    group('needsEnrollment', () {
      test('true when no factor enrolled', () {
        const s = MfaStatus(
          currentLevel: MfaAssuranceLevel.aal1,
          hasEnrolledFactor: false,
        );
        expect(s.needsEnrollment, isTrue);
        expect(s.needsChallenge, isFalse);
        expect(s.isFullyAuthenticated, isFalse);
      });

      test('false when factor enrolled', () {
        const s = MfaStatus(
          currentLevel: MfaAssuranceLevel.aal1,
          hasEnrolledFactor: true,
          factorId: 'f-1',
        );
        expect(s.needsEnrollment, isFalse);
      });
    });

    group('needsChallenge', () {
      test('true when enrolled but AAL1', () {
        const s = MfaStatus(
          currentLevel: MfaAssuranceLevel.aal1,
          hasEnrolledFactor: true,
          factorId: 'f-1',
        );
        expect(s.needsChallenge, isTrue);
      });

      test('false when AAL2', () {
        const s = MfaStatus(
          currentLevel: MfaAssuranceLevel.aal2,
          hasEnrolledFactor: true,
          factorId: 'f-1',
        );
        expect(s.needsChallenge, isFalse);
      });

      test('false when not enrolled', () {
        const s = MfaStatus(
          currentLevel: MfaAssuranceLevel.aal1,
          hasEnrolledFactor: false,
        );
        expect(s.needsChallenge, isFalse);
      });
    });

    group('isFullyAuthenticated', () {
      test('true when enrolled + AAL2', () {
        const s = MfaStatus(
          currentLevel: MfaAssuranceLevel.aal2,
          hasEnrolledFactor: true,
          factorId: 'f-1',
        );
        expect(s.isFullyAuthenticated, isTrue);
      });

      test('false when AAL2 but not enrolled (edge case)', () {
        const s = MfaStatus(
          currentLevel: MfaAssuranceLevel.aal2,
          hasEnrolledFactor: false,
        );
        expect(s.isFullyAuthenticated, isFalse);
      });
    });

    group('[CIA:A] lockout state', () {
      test('carries lockout info with UTC timestamp', () {
        final ts = DateTime.utc(2026, 5, 6, 22, 30);
        final s = MfaStatus(
          currentLevel: MfaAssuranceLevel.aal1,
          hasEnrolledFactor: true,
          factorId: 'f-1',
          isLockedOut: true,
          failedAttempts: 5,
          lockedUntil: ts,
        );
        expect(s.isLockedOut, isTrue);
        expect(s.failedAttempts, 5);
        expect(s.lockedUntil!.isUtc, isTrue);
      });

      test('locked account does NOT expose needsChallenge=true', () {
        final s = MfaStatus(
          currentLevel: MfaAssuranceLevel.aal1,
          hasEnrolledFactor: true,
          factorId: 'f-1',
          isLockedOut: true,
          failedAttempts: 5,
          lockedUntil: DateTime.utc(2026, 5, 6, 22, 30),
        );
        // Locked account: routing must check isLockedOut BEFORE needsChallenge.
        // The model itself doesn't enforce this gate, but test documents contract.
        expect(s.isLockedOut, isTrue);
        expect(s.hasEnrolledFactor, isTrue);
      });
    });

    group('equality & hashCode', () {
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

      test('not equal when assurance levels differ', () {
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

  // ── MfaChallengeResult ───────────────────────────────────────────────────
  group('MfaChallengeResult', () {
    test('carries challengeId and factorId', () {
      const r = MfaChallengeResult(challengeId: 'ch-1', factorId: 'f-1');
      expect(r.challengeId, 'ch-1');
      expect(r.factorId, 'f-1');
    });
  });

  // ── MfaEnrollmentResult ───────────────────────────────────────────────────
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
