import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/admin/update_org_settings_command.dart';
import 'package:veraprob/application/admin/update_org_settings_handler.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/domain/admin/org_status.dart';
import 'package:veraprob/domain/admin/organization.dart';
import 'package:veraprob/domain/admin/organization_repository.dart';
import 'package:veraprob/domain/enums/user_role.dart';

class MockOrganizationRepository extends Mock
    implements OrganizationRepository {}

class MockTenantValidationService extends Mock
    implements TenantValidationService {}

void main() {
  late MockOrganizationRepository repository;
  late MockTenantValidationService tenantValidator;
  late UpdateOrgSettingsHandler handler;

  setUpAll(() {
    registerFallbackValue(
      Organization(
        id: '',
        name: '',
        timezone: '',
        currencyCode: '',
        status: OrgStatus.active,
        createdAt: DateTime.now().toUtc(),
      ),
    );
  });

  final org = Organization(
    id: 'org-1',
    name: 'Old Name',
    timezone: 'UTC',
    currencyCode: 'BRL',
    status: OrgStatus.active,
    createdAt: DateTime.now().toUtc(),
  );

  setUp(() {
    repository = MockOrganizationRepository();
    tenantValidator = MockTenantValidationService();
    handler = UpdateOrgSettingsHandler(
      tenantValidator: tenantValidator,
      repository: repository,
    );

    // Default: tenant validation passes
    when(
      () => tenantValidator.assertTenantMatches(
        payloadOrgId: any(named: 'payloadOrgId'),
        sessionId: any(named: 'sessionId'),
      ),
    ).thenAnswer((_) async => {});

    // Default mock behavior for successful org lookup
    when(() => repository.findById(any())).thenAnswer((_) async => org);
  });

  UpdateOrgSettingsCommand makeCommand({UserRole role = UserRole.superAdmin}) {
    return UpdateOrgSettingsCommand(
      organizationId: 'org-1',
      callerRole: role,
      name: 'New Name',
      timezone: 'America/Sao_Paulo',
      currencyCode: 'USD',
      sessionId: 'session-1',
    );
  }

  group('UpdateOrgSettingsHandler', () {
    test('Rejeita operator/auditor/admin para campos criticos', () async {
      expect(
        () => handler.handle(makeCommand(role: UserRole.operator)),
        throwsException,
      );
      expect(
        () => handler.handle(makeCommand(role: UserRole.auditor)),
        throwsException,
      );
      expect(
        () => handler.handle(makeCommand(role: UserRole.admin)),
        throwsException,
      );
      verifyNever(() => repository.update(any()));
    });

    test('Passa para superAdmin com args corretos', () async {
      when(() => repository.findById('org-1')).thenAnswer((_) async => org);
      when(() => repository.update(any())).thenAnswer((_) async => {});

      await handler.handle(makeCommand(role: UserRole.superAdmin));

      final captured =
          verify(() => repository.update(captureAny())).captured.single
              as Organization;
      expect(captured.name, 'New Name');
      expect(captured.timezone, 'America/Sao_Paulo');
      expect(captured.currencyCode, 'USD');
      expect(captured.id, 'org-1');
    });

    test('Erro quando organizacao nao existe', () async {
      when(() => repository.findById('org-1')).thenAnswer((_) async => null);

      expect(
        () => handler.handle(makeCommand(role: UserRole.admin)),
        throwsException,
      );
    });
  });
}
