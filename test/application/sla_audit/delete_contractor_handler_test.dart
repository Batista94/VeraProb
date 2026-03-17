import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pactaflow/application/sla_audit/delete_contractor_command.dart';
import 'package:pactaflow/application/sla_audit/delete_contractor_handler.dart';
import 'package:pactaflow/domain/sla_audit/contractor_repository.dart';
import 'package:pactaflow/domain/enums/user_role.dart';

class MockContractorRepository extends Mock implements ContractorRepository {}

void main() {
  late MockContractorRepository repository;
  late DeleteContractorHandler handler;

  setUp(() {
    repository = MockContractorRepository();
    handler = DeleteContractorHandler(repository: repository);
  });

  DeleteContractorCommand makeCommand({UserRole role = UserRole.admin}) {
    return DeleteContractorCommand(
      organizationId: 'org-1',
      callerRole: role,
      contractorId: 'contractor-1',
    );
  }

  group('DeleteContractorHandler', () {
    test('Rejeita auditor', () async {
      expect(() => handler.handle(makeCommand(role: UserRole.auditor)), throwsException);
      verifyNever(() => repository.delete(any(), any()));
    });

    test('Passa para admin e operator (chama repo com args corretos)', () async {
      when(() => repository.delete('org-1', 'contractor-1')).thenAnswer((_) async => {});

      await handler.handle(makeCommand(role: UserRole.admin));
      await handler.handle(makeCommand(role: UserRole.operator));

      verify(() => repository.delete('org-1', 'contractor-1')).called(2);
    });
  });
}
