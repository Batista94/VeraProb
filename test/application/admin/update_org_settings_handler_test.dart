import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/admin/update_org_settings_command.dart';
import 'package:veraprob/application/admin/update_org_settings_handler.dart';
import 'package:veraprob/domain/admin/organization.dart';
import 'package:veraprob/domain/admin/organization_repository.dart';
import 'package:veraprob/domain/enums/user_role.dart';

class MockOrganizationRepository extends Mock implements OrganizationRepository {}

void main() {
  late MockOrganizationRepository repository;
  late UpdateOrgSettingsHandler handler;

  setUpAll(() {
    registerFallbackValue(Organization(
      id: '',
      name: '',
      timezone: '',
      currencyCode: '',
      isActive: true,
      createdAt: DateTime.now(),
    ));
  });

  setUp(() {
    repository = MockOrganizationRepository();
    handler = UpdateOrgSettingsHandler(repository: repository);
  });

  final org = Organization(
    id: 'org-1',
    name: 'Old Name',
    timezone: 'UTC',
    currencyCode: 'BRL',
    isActive: true,
    createdAt: DateTime.now(),
  );

  UpdateOrgSettingsCommand makeCommand({UserRole role = UserRole.admin}) {
    return UpdateOrgSettingsCommand(
      organizationId: 'org-1',
      callerRole: role,
      name: 'New Name',
      timezone: 'America/Sao_Paulo',
      currencyCode: 'USD',
    );
  }

  group('UpdateOrgSettingsHandler', () {
    test('Rejeita operator/auditor', () async {
      expect(() => handler.handle(makeCommand(role: UserRole.operator)), throwsException);
      expect(() => handler.handle(makeCommand(role: UserRole.auditor)), throwsException);
      verifyNever(() => repository.update(any()));
    });

    test('Passa para admin com args corretos', () async {
      when(() => repository.findById('org-1')).thenAnswer((_) async => org);
      when(() => repository.update(any())).thenAnswer((_) async => {});

      await handler.handle(makeCommand(role: UserRole.admin));

      final captured = verify(() => repository.update(captureAny())).captured.single as Organization;
      expect(captured.name, 'New Name');
      expect(captured.timezone, 'America/Sao_Paulo');
      expect(captured.currencyCode, 'USD');
      expect(captured.id, 'org-1');
    });
    
    test('Erro quando organização não existe', () async {
      when(() => repository.findById('org-1')).thenAnswer((_) async => null);
      
      expect(() => handler.handle(makeCommand(role: UserRole.admin)), throwsException);
    });
  });
}
