import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/admin/update_org_settings_command.dart';
import 'package:veraprob/application/admin/update_org_settings_handler.dart';
import 'package:veraprob/application/audit/system_audit_log_service.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/domain/admin/actor_type.dart';
import 'package:veraprob/domain/admin/org_capabilities.dart';
import 'package:veraprob/domain/admin/org_status.dart';
import 'package:veraprob/domain/admin/organization.dart';
import 'package:veraprob/domain/admin/organization_repository.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';

class MockSystemAuditLogService extends Mock implements SystemAuditLogService {}

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
    registerFallbackValue(ActorType.human);
    registerFallbackValue(<String, Object?>{});
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

  group(
    'UpdateOrgSettingsHandler — capability change justification (INV-10)',
    () {
      late MockSystemAuditLogService auditLog;

      setUp(() {
        auditLog = MockSystemAuditLogService();
        handler = UpdateOrgSettingsHandler(
          tenantValidator: tenantValidator,
          repository: repository,
          auditLogService: auditLog,
        );
        when(() => repository.findById(any())).thenAnswer((_) async => org);
        when(() => repository.update(any())).thenAnswer((_) async => {});
        when(
          () => auditLog.logGovernanceChange(
            eventType: any(named: 'eventType'),
            reason: any(named: 'reason'),
            actorType: any(named: 'actorType'),
            organizationId: any(named: 'organizationId'),
            organizationName: any(named: 'organizationName'),
            oldSnapshot: any(named: 'oldSnapshot'),
            newSnapshot: any(named: 'newSnapshot'),
            source: any(named: 'source'),
            impersonatorId: any(named: 'impersonatorId'),
          ),
        ).thenAnswer((_) async {});
      });

      test('capability change sem reason lança DomainException', () async {
        final cmd = UpdateOrgSettingsCommand(
          organizationId: 'org-1',
          callerRole: UserRole.admin,
          capabilities: const OrgCapabilities(allowsSealing: false),
          sessionId: 'session-1',
        );
        expect(() => handler.handle(cmd), throwsA(isA<DomainException>()));
        verifyNever(() => repository.update(any()));
      });

      test(
        'capability change com reason < 10 chars lança DomainException',
        () async {
          final cmd = UpdateOrgSettingsCommand(
            organizationId: 'org-1',
            callerRole: UserRole.admin,
            capabilities: const OrgCapabilities(allowsSealing: false),
            reason: 'curto',
            sessionId: 'session-1',
          );
          expect(() => handler.handle(cmd), throwsA(isA<DomainException>()));
          verifyNever(() => repository.update(any()));
        },
      );

      test(
        'capability change com reason válida persiste e loga audit',
        () async {
          final cmd = UpdateOrgSettingsCommand(
            organizationId: 'org-1',
            callerRole: UserRole.admin,
            capabilities: const OrgCapabilities(allowsSealing: false),
            reason: 'Desativando lacre por solicitação operacional',
            sessionId: 'session-1',
          );
          await handler.handle(cmd);

          verify(() => repository.update(any())).called(1);
          verify(
            () => auditLog.logGovernanceChange(
              eventType: any(named: 'eventType'),
              reason: 'Desativando lacre por solicitação operacional',
              actorType: ActorType.human,
              organizationId: 'org-1',
              organizationName: any(named: 'organizationName'),
              oldSnapshot: any(named: 'oldSnapshot'),
              newSnapshot: any(named: 'newSnapshot'),
              source: any(named: 'source'),
              impersonatorId: any(named: 'impersonatorId'),
            ),
          ).called(1);
        },
      );

      test('sem capability change não exige reason e não loga audit', () async {
        final cmd = UpdateOrgSettingsCommand(
          organizationId: 'org-1',
          callerRole: UserRole.admin,
          logoUrl: 'https://example.com/logo.png',
          sessionId: 'session-1',
        );
        await handler.handle(cmd);

        verify(() => repository.update(any())).called(1);
        verifyNever(
          () => auditLog.logGovernanceChange(
            eventType: any(named: 'eventType'),
            reason: any(named: 'reason'),
            actorType: any(named: 'actorType'),
            organizationId: any(named: 'organizationId'),
            organizationName: any(named: 'organizationName'),
            oldSnapshot: any(named: 'oldSnapshot'),
            newSnapshot: any(named: 'newSnapshot'),
            source: any(named: 'source'),
            impersonatorId: any(named: 'impersonatorId'),
          ),
        );
      });
    },
  );
}
