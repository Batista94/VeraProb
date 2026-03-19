import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/admin/invitation_command_service.dart';
import 'package:veraprob/application/admin/revoke_invitation_command.dart';
import 'package:veraprob/application/admin/revoke_invitation_handler.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';

class MockInvitationCommandService extends Mock
    implements InvitationCommandService {}

void main() {
  late MockInvitationCommandService commandService;
  late RevokeInvitationHandler handler;

  setUpAll(() {
    registerFallbackValue(UserRole.operator);
    registerFallbackValue(DateTime.now());
  });

  setUp(() {
    commandService = MockInvitationCommandService();
    handler = RevokeInvitationHandler(commandService);
  });

  void stubRevoke() {
    when(() => commandService.revokeInvitation(
          invitationId: any(named: 'invitationId'),
        )).thenAnswer((_) async {});
  }

  RevokeInvitationCommand makeCommand({UserRole callerRole = UserRole.admin}) {
    return RevokeInvitationCommand(
      organizationId: 'org-1',
      callerRole: callerRole,
      invitationId: 'inv-uuid-1',
    );
  }

  group('RevokeInvitationHandler', () {
    test('Rejeita operator — não tem canManageUsers', () async {
      await expectLater(
        () => handler.handle(makeCommand(callerRole: UserRole.operator)),
        throwsA(isA<DomainException>()),
      );
      verifyNever(() => commandService.revokeInvitation(
            invitationId: any(named: 'invitationId'),
          ));
    });

    test('Rejeita auditor — não tem canManageUsers', () async {
      await expectLater(
        () => handler.handle(makeCommand(callerRole: UserRole.auditor)),
        throwsA(isA<DomainException>()),
      );
      verifyNever(() => commandService.revokeInvitation(
            invitationId: any(named: 'invitationId'),
          ));
    });

    test('Admin revoga com sucesso — delega para commandService', () async {
      stubRevoke();

      await handler.handle(makeCommand(callerRole: UserRole.admin));

      verify(() => commandService.revokeInvitation(
            invitationId: 'inv-uuid-1',
          )).called(1);
    });
  });
}
