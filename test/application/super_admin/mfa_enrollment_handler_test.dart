import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/features/super_admin/application/mfa_enrollment_handler.dart';
import 'package:veraprob/features/super_admin/domain/i_mfa_repository.dart';
import 'package:veraprob/features/super_admin/domain/mfa_enrollment_result.dart';
import 'package:veraprob/features/super_admin/domain/mfa_status.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';

class MockMfaRepository extends Mock implements IMfaRepository {}

void main() {
  late MockMfaRepository mockRepo;
  late MfaEnrollmentHandler handler;

  setUp(() {
    mockRepo = MockMfaRepository();
    handler = MfaEnrollmentHandler(mockRepo);
  });

  group('MfaEnrollmentHandler', () {
    test('delegates to enrollTotp when no factor enrolled', () async {
      const enrollResult = MfaEnrollmentResult(
        factorId: 'factor-abc',
        totpUri: 'otpauth://totp/VeraProb?secret=BASE32SECRET',
        secret: 'BASE32SECRET',
        recoveryCodes: ['CODE1', 'CODE2', 'CODE3'],
      );

      when(() => mockRepo.getMfaStatus()).thenAnswer(
        (_) async => const MfaStatus(
          currentLevel: MfaAssuranceLevel.aal1,
          hasEnrolledFactor: false,
        ),
      );
      when(() => mockRepo.enrollTotp()).thenAnswer((_) async => enrollResult);

      final result = await handler.handle();

      expect(result.factorId, 'factor-abc');
      expect(result.totpUri, contains('otpauth://'));
      expect(result.recoveryCodes, hasLength(3));
      verify(() => mockRepo.enrollTotp()).called(1);
    });

    test('throws DomainException when factor already enrolled', () async {
      when(() => mockRepo.getMfaStatus()).thenAnswer(
        (_) async => const MfaStatus(
          currentLevel: MfaAssuranceLevel.aal1,
          hasEnrolledFactor: true,
          factorId: 'existing-factor',
        ),
      );

      expect(() => handler.handle(), throwsA(isA<DomainException>()));
      verifyNever(() => mockRepo.enrollTotp());
    });
  });
}
