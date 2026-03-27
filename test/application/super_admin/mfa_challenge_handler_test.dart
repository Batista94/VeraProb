import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/super_admin/mfa_challenge_handler.dart';
import 'package:veraprob/domain/super_admin/i_mfa_repository.dart';
import 'package:veraprob/domain/super_admin/mfa_challenge_result.dart';
import 'package:veraprob/domain/super_admin/mfa_status.dart';
import 'package:veraprob/domain/super_admin/mfa_verification_result.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';

class MockMfaRepository extends Mock implements IMfaRepository {}

void main() {
  late MockMfaRepository mockRepo;
  late MfaChallengeHandler handler;

  setUp(() {
    mockRepo = MockMfaRepository();
    handler = MfaChallengeHandler(mockRepo);
  });

  group('MfaChallengeHandler', () {
    group('createChallenge', () {
      test('creates challenge when enrolled and not locked', () async {
        when(() => mockRepo.getMfaStatus()).thenAnswer(
          (_) async => const MfaStatus(
            currentLevel: MfaAssuranceLevel.aal1,
            hasEnrolledFactor: true,
            factorId: 'factor-123',
          ),
        );
        when(() => mockRepo.createChallenge('factor-123')).thenAnswer(
          (_) async => const MfaChallengeResult(
            challengeId: 'challenge-abc',
            factorId: 'factor-123',
          ),
        );

        final result = await handler.createChallenge();

        expect(result.challengeId, 'challenge-abc');
        expect(result.factorId, 'factor-123');
      });

      test('throws when no factor enrolled', () async {
        when(() => mockRepo.getMfaStatus()).thenAnswer(
          (_) async => const MfaStatus(
            currentLevel: MfaAssuranceLevel.aal1,
            hasEnrolledFactor: false,
          ),
        );

        expect(
          () => handler.createChallenge(),
          throwsA(isA<DomainException>()),
        );
      });

      test('throws when account is locked out', () async {
        when(() => mockRepo.getMfaStatus()).thenAnswer(
          (_) async => MfaStatus(
            currentLevel: MfaAssuranceLevel.aal1,
            hasEnrolledFactor: true,
            factorId: 'factor-123',
            isLockedOut: true,
            failedAttempts: 5,
            lockedUntil: DateTime.utc(2026, 3, 27, 13, 0),
          ),
        );

        expect(
          () => handler.createChallenge(),
          throwsA(isA<DomainException>()),
        );
      });
    });

    group('verify', () {
      test('delegates to verifyChallenge on repository', () async {
        when(
          () => mockRepo.verifyChallenge(
            factorId: 'factor-123',
            challengeId: 'challenge-abc',
            code: '123456',
          ),
        ).thenAnswer((_) async => const MfaVerificationSuccess());

        final result = await handler.verify(
          factorId: 'factor-123',
          challengeId: 'challenge-abc',
          code: '123456',
        );

        expect(result, isA<MfaVerificationSuccess>());
      });

      test('returns failure with lockout details', () async {
        final lockedUntil = DateTime.utc(2026, 3, 27, 13, 0);
        when(
          () => mockRepo.verifyChallenge(
            factorId: 'factor-123',
            challengeId: 'challenge-abc',
            code: '000000',
          ),
        ).thenAnswer(
          (_) async => MfaVerificationFailure(
            failedAttempts: 5,
            isLockedOut: true,
            lockedUntil: lockedUntil,
            message: 'Conta bloqueada.',
          ),
        );

        final result = await handler.verify(
          factorId: 'factor-123',
          challengeId: 'challenge-abc',
          code: '000000',
        );

        expect(result, isA<MfaVerificationFailure>());
        final failure = result as MfaVerificationFailure;
        expect(failure.isLockedOut, isTrue);
        expect(failure.failedAttempts, 5);
      });
    });
  });
}
