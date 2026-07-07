import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/admin/reactivate_member_handler.dart';
import 'package:veraprob/application/admin/remove_member_command.dart';
import 'package:veraprob/application/admin/user_management_command_service.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/shared/sovereignty_violation_exception.dart';

class MockUserManagementCommandService extends Mock
    implements UserManagementCommandService {}

class MockTenantValidationService extends Mock
    implements TenantValidationService {}

void main() {
  late MockUserManagementCommandService commandService;
  late MockTenantValidationService tenantValidator;
  late ReactivateMemberHandler handler;

  setUp(() {
    commandService = MockUserManagementCommandService();
    tenantValidator = MockTenantValidationService();
    handler = ReactivateMemberHandler(
      tenantValidator: tenantValidator,
      commandService: commandService,
    );

    when(
      () => tenantValidator.assertTenantMatches(
        payloadOrgId: any(named: 'payloadOrgId'),
        sessionId: any(named: 'sessionId'),
      ),
    ).thenAnswer((_) async {});
  });

  RemoveMemberCommand makeCommand({
    UserRole role = UserRole.admin,
    String targetId = 'user-2',
  }) {
    return RemoveMemberCommand(
      organizationId: 'org-1',
      callerRole: role,
      targetUserId: targetId,
      sessionId: 'session-1',
    );
  }

  group('ReactivateMemberHandler', () {
    test('reativa com sucesso quando o chamador tem canManageUsers', () async {
      when(
        () => commandService.reactivateMember(
          organizationId: any(named: 'organizationId'),
          targetUserId: any(named: 'targetUserId'),
        ),
      ).thenAnswer((_) async {});

      await handler.handle(makeCommand());

      verify(
        () => commandService.reactivateMember(
          organizationId: 'org-1',
          targetUserId: 'user-2',
        ),
      ).called(1);
    });

    test('rejeita chamador sem canManageUsers (operator/auditor)', () async {
      expect(
        () => handler.handle(makeCommand(role: UserRole.operator)),
        throwsException,
      );
      expect(
        () => handler.handle(makeCommand(role: UserRole.auditor)),
        throwsException,
      );

      verifyNever(
        () => commandService.reactivateMember(
          organizationId: any(named: 'organizationId'),
          targetUserId: any(named: 'targetUserId'),
        ),
      );
    });

    test('propaga violacao de tenant (mismatch de organizationId)', () async {
      when(
        () => tenantValidator.assertTenantMatches(
          payloadOrgId: any(named: 'payloadOrgId'),
          sessionId: any(named: 'sessionId'),
        ),
      ).thenThrow(
        const SovereigntyViolationException(
          payloadOrgId: 'org-1',
          jwtOrgId: 'org-2',
        ),
      );

      await expectLater(
        () => handler.handle(makeCommand()),
        throwsA(isA<SovereigntyViolationException>()),
      );

      verifyNever(
        () => commandService.reactivateMember(
          organizationId: any(named: 'organizationId'),
          targetUserId: any(named: 'targetUserId'),
        ),
      );
    });
  });
}
