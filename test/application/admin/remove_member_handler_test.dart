import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/admin/remove_member_command.dart';
import 'package:veraprob/application/admin/remove_member_handler.dart';
import 'package:veraprob/application/admin/user_management_command_service.dart';
import 'package:veraprob/application/admin/user_management_query_service.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/shared/sovereignty_violation_exception.dart';
import 'package:veraprob/infrastructure/admin/postgres_user_management_query_service.dart';

class MockUserManagementCommandService extends Mock
    implements UserManagementCommandService {}

class MockUserManagementQueryService extends Mock
    implements PostgresUserManagementQueryService {}

class MockTenantValidationService extends Mock
    implements TenantValidationService {}

void main() {
  late MockUserManagementCommandService commandService;
  late MockUserManagementQueryService queryService;
  late MockTenantValidationService tenantValidator;
  late RemoveMemberHandler handler;

  setUp(() {
    commandService = MockUserManagementCommandService();
    queryService = MockUserManagementQueryService();
    tenantValidator = MockTenantValidationService();
    handler = RemoveMemberHandler(
      tenantValidator: tenantValidator,
      commandService: commandService,
      queryService: queryService,
    );

    // Default: tenant validation passes
    when(
      () => tenantValidator.assertTenantMatches(
        payloadOrgId: any(named: 'payloadOrgId'),
        sessionId: any(named: 'sessionId'),
      ),
    ).thenAnswer((_) async => {});
  });

  RemoveMemberCommand makeCommand({
    UserRole role = UserRole.admin,
    String targetId = 'user-2',
  }) {
    return RemoveMemberCommand(
      organizationId: 'org-1',
      callerRole: role,
      callerUserId: 'user-admin',
      targetUserId: targetId,
      sessionId: 'session-1',
    );
  }

  group('RemoveMemberHandler', () {
    test('Rejeita nao-admin (operator/auditor)', () async {
      expect(
        () => handler.handle(makeCommand(role: UserRole.operator)),
        throwsException,
      );
      expect(
        () => handler.handle(makeCommand(role: UserRole.auditor)),
        throwsException,
      );
    });

    test('Rejeita remocao do ultimo admin', () async {
      final members = [
        OrgMember(
          userId: 'user-1',
          email: 'a@a.com',
          role: UserRole.admin,
          invitedAt: DateTime.now().toUtc(),
        ),
        OrgMember(
          userId: 'user-2',
          email: 'b@b.com',
          role: UserRole.operator,
          invitedAt: DateTime.now().toUtc(),
        ),
      ];
      when(() => queryService.getMembers()).thenAnswer((_) async => members);

      final cmd = makeCommand(targetId: 'user-1');
      expect(
        () => handler.handle(cmd),
        throwsA(
          predicate(
            (e) =>
                e.toString().contains(
                  'Nao e possivel remover o unico administrador',
                ) ||
                e.toString().contains(
                  'Não é possível remover o único administrador',
                ),
          ),
        ),
      );

      verifyNever(
        () => commandService.removeMember(
          organizationId: any(named: 'organizationId'),
          targetUserId: any(named: 'targetUserId'),
        ),
      );
    });

    test('Passa quando >= 1 admin restante', () async {
      final members = [
        OrgMember(
          userId: 'user-1',
          email: 'a@a.com',
          role: UserRole.admin,
          invitedAt: DateTime.now().toUtc(),
        ),
        OrgMember(
          userId: 'user-2',
          email: 'b@b.com',
          role: UserRole.admin,
          invitedAt: DateTime.now().toUtc(),
        ),
      ];
      when(() => queryService.getMembers()).thenAnswer((_) async => members);
      when(
        () => commandService.removeMember(
          organizationId: any(named: 'organizationId'),
          targetUserId: any(named: 'targetUserId'),
        ),
      ).thenAnswer((_) async => {});

      await handler.handle(makeCommand(targetId: 'user-2'));

      verify(
        () => commandService.removeMember(
          organizationId: 'org-1',
          targetUserId: 'user-2',
        ),
      ).called(1);
    });

    test('Erro quando membro nao encontrado', () async {
      when(() => queryService.getMembers()).thenAnswer((_) async => []);

      expect(
        () => handler.handle(makeCommand(targetId: 'ghost')),
        throwsException,
      );
    });

    test(
      'tenant mismatch → SovereigntyViolationException e nao consulta membros '
      '(INV-1 / anti privilege-escalation)',
      () async {
        when(
          () => tenantValidator.assertTenantMatches(
            payloadOrgId: any(named: 'payloadOrgId'),
            sessionId: any(named: 'sessionId'),
          ),
        ).thenThrow(
          const SovereigntyViolationException(
            payloadOrgId: 'org-1',
            jwtOrgId: 'org-attacker',
          ),
        );

        await expectLater(
          () => handler.handle(makeCommand()),
          throwsA(isA<SovereigntyViolationException>()),
        );

        verifyNever(() => queryService.getMembers());
        verifyNever(
          () => commandService.removeMember(
            organizationId: any(named: 'organizationId'),
            targetUserId: any(named: 'targetUserId'),
          ),
        );
      },
    );
  });
}
