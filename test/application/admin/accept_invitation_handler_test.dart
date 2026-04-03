import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/admin/invitation_command_service.dart';
import 'package:veraprob/application/admin/accept_invitation_command.dart';
import 'package:veraprob/application/admin/accept_invitation_handler.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';

class MockInvitationCommandService extends Mock
    implements InvitationCommandService {}

void main() {
  late MockInvitationCommandService commandService;
  late AcceptInvitationHandler handler;

  setUpAll(() {
    registerFallbackValue(UserRole.operator);
    registerFallbackValue(DateTime.now().toUtc());
  });

  setUp(() {
    commandService = MockInvitationCommandService();
    handler = AcceptInvitationHandler(commandService);
  });

  void stubAccept() {
    when(
      () => commandService.acceptInvitation(
        token: any(named: 'token'),
        userId: any(named: 'userId'),
      ),
    ).thenAnswer((_) async {});
  }

  group('AcceptInvitationHandler', () {
    test('Token vazio lança DomainException sem chamar RPC', () async {
      await expectLater(
        () => handler.handle(
          const AcceptInvitationCommand(token: '  ', userId: 'user-1'),
        ),
        throwsA(isA<DomainException>()),
      );
      verifyNever(
        () => commandService.acceptInvitation(
          token: any(named: 'token'),
          userId: any(named: 'userId'),
        ),
      );
    });

    test('UserId vazio lança DomainException sem chamar RPC', () async {
      await expectLater(
        () => handler.handle(
          const AcceptInvitationCommand(token: 'valid-token', userId: ''),
        ),
        throwsA(isA<DomainException>()),
      );
      verifyNever(
        () => commandService.acceptInvitation(
          token: any(named: 'token'),
          userId: any(named: 'userId'),
        ),
      );
    });

    test('Token e userId válidos delegam para commandService', () async {
      stubAccept();

      await handler.handle(
        const AcceptInvitationCommand(token: 'abc-token', userId: 'user-1'),
      );

      verify(
        () => commandService.acceptInvitation(
          token: 'abc-token',
          userId: 'user-1',
        ),
      ).called(1);
    });
  });
}
