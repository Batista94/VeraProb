import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/admin/invitation_command_service.dart';
import 'package:veraprob/application/admin/invite_user_command.dart';
import 'package:veraprob/application/admin/invite_user_handler.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';

import '../../mocks/fake_date_time_provider.dart';

class MockInvitationCommandService extends Mock
    implements InvitationCommandService {}

class MockTenantValidationService extends Mock
    implements TenantValidationService {}

void main() {
  late MockInvitationCommandService commandService;
  late FakeDateTimeProvider dateTimeProvider;
  late MockTenantValidationService tenantValidator;
  late InviteUserHandler handler;

  setUpAll(() {
    registerFallbackValue(UserRole.operator);
    registerFallbackValue(DateTime.now().toUtc());
  });

  setUp(() {
    commandService = MockInvitationCommandService();
    dateTimeProvider = FakeDateTimeProvider(DateTime(2026, 4, 7, 21, 0, 0));
    tenantValidator = MockTenantValidationService();
    handler = InviteUserHandler(
      tenantValidator: tenantValidator,
      commandService: commandService,
      dateTimeProvider: dateTimeProvider,
    );

    // Default: tenant validation passes
    when(
      () => tenantValidator.assertTenantMatches(
        payloadOrgId: any(named: 'payloadOrgId'),
        sessionId: any(named: 'sessionId'),
      ),
    ).thenAnswer((_) async => {});
  });

  void stubInviteUser() {
    when(
      () => commandService.inviteUser(
        email: any(named: 'email'),
        role: any(named: 'role'),
        token: any(named: 'token'),
        invitationId: any(named: 'invitationId'),
        expiresAtUtc: any(named: 'expiresAtUtc'),
      ),
    ).thenAnswer((_) async {});
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
      sessionId: 'session-1',
    );
  }

  group('InviteUserHandler', () {
    test('Rejeita operator — nao tem canInviteUsers', () async {
      await expectLater(
        () => handler.handle(makeCommand(callerRole: UserRole.operator)),
        throwsA(isA<DomainException>()),
      );
      verifyNever(
        () => commandService.inviteUser(
          email: any(named: 'email'),
          role: any(named: 'role'),
          token: any(named: 'token'),
          invitationId: any(named: 'invitationId'),
          expiresAtUtc: any(named: 'expiresAtUtc'),
        ),
      );
    });

    test('Rejeita auditor — nao tem canInviteUsers', () async {
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

    test('Admin convida com sucesso — retorna token nao-vazio', () async {
      stubInviteUser();

      final token = await handler.handle(makeCommand());

      expect(token, isNotEmpty);
      verify(
        () => commandService.inviteUser(
          email: 'novo@empresa.com',
          role: UserRole.operator,
          token: any(named: 'token'),
          invitationId: any(named: 'invitationId'),
          expiresAtUtc: any(named: 'expiresAtUtc'),
        ),
      ).called(1);
    });

    test('Tokens gerados em duas invocacoes sao distintos', () async {
      stubInviteUser();

      final token1 = await handler.handle(makeCommand());
      final token2 = await handler.handle(makeCommand());

      expect(token1, isNot(equals(token2)));
    });

    test('Email e normalizado para lowercase', () async {
      stubInviteUser();

      await handler.handle(makeCommand(email: '  NOVO@EMPRESA.COM  '));

      verify(
        () => commandService.inviteUser(
          email: 'novo@empresa.com',
          role: any(named: 'role'),
          token: any(named: 'token'),
          invitationId: any(named: 'invitationId'),
          expiresAtUtc: any(named: 'expiresAtUtc'),
        ),
      ).called(1);
    });
  });
}
