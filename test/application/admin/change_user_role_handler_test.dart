import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/admin/change_user_role_command.dart';
import 'package:veraprob/application/admin/change_user_role_handler.dart';
import 'package:veraprob/application/admin/user_management_command_service.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/domain/enums/user_role.dart';

class MockUserManagementCommandService extends Mock
    implements UserManagementCommandService {}

class MockTenantValidationService extends Mock
    implements TenantValidationService {}

void main() {
  late MockUserManagementCommandService commandService;
  late MockTenantValidationService tenantValidator;
  late ChangeUserRoleHandler handler;

  setUpAll(() {
    registerFallbackValue(UserRole.operator);
  });

  setUp(() {
    commandService = MockUserManagementCommandService();
    tenantValidator = MockTenantValidationService();
    handler = ChangeUserRoleHandler(
      tenantValidator: tenantValidator,
      commandService: commandService,
    );

    // Default: tenant validation passes
    when(
      () => tenantValidator.assertTenantMatches(
        payloadOrgId: any(named: 'payloadOrgId'),
        sessionId: any(named: 'sessionId'),
      ),
    ).thenAnswer((_) async => {});
  });

  ChangeUserRoleCommand makeCommand({UserRole role = UserRole.admin}) {
    return ChangeUserRoleCommand(
      organizationId: 'org-1',
      callerRole: role,
      targetUserId: 'user-2',
      newRole: UserRole.operator,
      sessionId: 'session-1',
    );
  }

  group('ChangeUserRoleHandler', () {
    test('Rejeita não-admin (operator/auditor)', () async {
      expect(
        () => handler.handle(makeCommand(role: UserRole.operator)),
        throwsException,
      );
      expect(
        () => handler.handle(makeCommand(role: UserRole.auditor)),
        throwsException,
      );

      verifyNever(
        () => commandService.changeRole(
          organizationId: any(named: 'organizationId'),
          targetUserId: any(named: 'targetUserId'),
          newRole: any(named: 'newRole'),
        ),
      );
    });

    test('Passa para admin válido', () async {
      when(
        () => commandService.changeRole(
          organizationId: any(named: 'organizationId'),
          targetUserId: any(named: 'targetUserId'),
          newRole: any(named: 'newRole'),
        ),
      ).thenAnswer((_) async => {});

      await handler.handle(makeCommand(role: UserRole.admin));

      verify(
        () => commandService.changeRole(
          organizationId: 'org-1',
          targetUserId: 'user-2',
          newRole: UserRole.operator,
        ),
      ).called(1);
    });
  });
}
