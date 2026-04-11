import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/application/sla_audit/delete_contractor_command.dart';
import 'package:veraprob/application/sla_audit/delete_contractor_handler.dart';
import 'package:veraprob/domain/auth/auth_user.dart' as domain;
import 'package:veraprob/domain/auth/i_auth_repository.dart';
import 'package:veraprob/domain/sla_audit/contractor_repository.dart';
import 'package:veraprob/domain/enums/user_role.dart';

class MockAuthRepository extends Mock implements IAuthRepository {}

class MockContractorRepository extends Mock implements ContractorRepository {}

void main() {
  late MockAuthRepository mockAuthRepo;
  late TenantValidationService tenantValidator;
  late MockContractorRepository repository;
  late DeleteContractorHandler handler;

  setUp(() {
    mockAuthRepo = MockAuthRepository();
    tenantValidator = TenantValidationService(authRepository: mockAuthRepo);
    repository = MockContractorRepository();
    handler = DeleteContractorHandler(
      tenantValidator: tenantValidator,
      repository: repository,
    );
    when(() => mockAuthRepo.getUserBySessionId(any())).thenAnswer(
      (_) async => const domain.AuthUser(
        id: 'user-1',
        email: 'test@test.com',
        tenantId: 'org-1',
      ),
    );
  });

  DeleteContractorCommand makeCommand({UserRole role = UserRole.admin}) {
    return DeleteContractorCommand(
      organizationId: 'org-1',
      callerRole: role,
      contractorId: 'contractor-1',
      sessionId: 'session-1',
    );
  }

  group('DeleteContractorHandler', () {
    test('Rejeita auditor', () async {
      expect(
        () => handler.handle(makeCommand(role: UserRole.auditor)),
        throwsException,
      );
      verifyNever(() => repository.delete(any(), any()));
    });

    test(
      'Passa para admin e operator (chama repo com args corretos)',
      () async {
        when(
          () => repository.delete('org-1', 'contractor-1'),
        ).thenAnswer((_) async => {});

        await handler.handle(makeCommand(role: UserRole.admin));
        await handler.handle(makeCommand(role: UserRole.operator));

        verify(() => repository.delete('org-1', 'contractor-1')).called(2);
      },
    );
  });
}
