import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/admin/change_user_role_command.dart';
import 'package:veraprob/application/admin/change_user_role_handler.dart';
import 'package:veraprob/application/admin/user_management_command_service.dart';
import 'package:veraprob/domain/enums/user_role.dart';

class MockUserManagementCommandService extends Mock
    implements UserManagementCommandService {}

void main() {
  late MockUserManagementCommandService commandService;
  late ChangeUserRoleHandler handler;

  setUpAll(() {
    registerFallbackValue(UserRole.operator);
  });

  setUp(() {
    commandService = MockUserManagementCommandService();
    handler = ChangeUserRoleHandler(commandService);
  });

  ChangeUserRoleCommand makeCommand({UserRole role = UserRole.admin}) {
    return ChangeUserRoleCommand(
      organizationId: 'org-1',
      callerRole: role,
      targetUserId: 'user-2',
      newRole: UserRole.operator,
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
