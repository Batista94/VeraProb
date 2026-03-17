import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pactaflow/application/admin/invitation_command_service.dart';
import 'package:pactaflow/application/admin/invite_user_command.dart';
import 'package:pactaflow/application/admin/invite_user_handler.dart';
import 'package:pactaflow/domain/enums/user_role.dart';
import 'package:pactaflow/domain/sla_audit/domain_exception.dart';

class MockInvitationCommandService extends Mock
    implements InvitationCommandService {}

void main() {
  late MockInvitationCommandService commandService;
  late InviteUserHandler handler;

  setUpAll(() {
    registerFallbackValue(UserRole.operator);
    registerFallbackValue(DateTime.now());
  });

  setUp(() {
    commandService = MockInvitationCommandService();
    handler = InviteUserHandler(commandService);
  });

  void stubInviteUser() {
    when(() => commandService.inviteUser(
          email: any(named: 'email'),
          role: any(named: 'role'),
          token: any(named: 'token'),
          invitationId: any(named: 'invitationId'),
          expiresAtUtc: any(named: 'expiresAtUtc'),
        )).thenAnswer((_) async {});
  }

  InviteUserCommand makeCommand({
    UserRole callerRole = UserRole.admin,
    String email = 'novo@empresa.com',
    UserRole roleToAssign = UserRole.operator,
  }) {
    return InviteUserCommand(
      organizationId: 'org-1',
      callerRole: callerRole,
      invitedByUserId: 'admin-user-1',
      email: email,
      roleToAssign: roleToAssign,
    );
  }

  group('InviteUserHandler', () {
    test('Rejeita operator — não tem canInviteUsers', () async {
      await expectLater(
        () => handler.handle(makeCommand(callerRole: UserRole.operator)),
        throwsA(isA<DomainException>()),
      );
      verifyNever(() => commandService.inviteUser(
            email: any(named: 'email'),
            role: any(named: 'role'),
            token: any(named: 'token'),
            invitationId: any(named: 'invitationId'),
            expiresAtUtc: any(named: 'expiresAtUtc'),
          ));
    });

    test('Rejeita auditor — não tem canInviteUsers', () async {
      await expectLater(
        () => handler.handle(makeCommand(callerRole: UserRole.auditor)),
        throwsA(isA<DomainException>()),
      );
    });

    test('Rejeita email sem @', () async {
      await expectLater(
        () => handler.handle(makeCommand(email: 'invalido')),
        throwsA(isA<DomainException>()),
      );
    });

    test('Rejeita email em branco', () async {
      await expectLater(
        () => handler.handle(makeCommand(email: '  ')),
        throwsA(isA<DomainException>()),
      );
    });

    test('Admin convida com sucesso — retorna token não-vazio', () async {
      stubInviteUser();

      final token = await handler.handle(makeCommand());

      expect(token, isNotEmpty);
      verify(() => commandService.inviteUser(
            email: 'novo@empresa.com',
            role: UserRole.operator,
            token: any(named: 'token'),
            invitationId: any(named: 'invitationId'),
            expiresAtUtc: any(named: 'expiresAtUtc'),
          )).called(1);
    });

    test('Tokens gerados em duas invocações são distintos', () async {
      stubInviteUser();

      final token1 = await handler.handle(makeCommand());
      final token2 = await handler.handle(makeCommand());

      expect(token1, isNot(equals(token2)));
    });

    test('Email é normalizado para lowercase', () async {
      stubInviteUser();

      await handler.handle(makeCommand(email: '  NOVO@EMPRESA.COM  '));

      verify(() => commandService.inviteUser(
            email: 'novo@empresa.com',
            role: any(named: 'role'),
            token: any(named: 'token'),
            invitationId: any(named: 'invitationId'),
            expiresAtUtc: any(named: 'expiresAtUtc'),
          )).called(1);
    });
  });
}
