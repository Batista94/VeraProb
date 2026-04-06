import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/admin/remove_member_command.dart';
import 'package:veraprob/application/admin/remove_member_handler.dart';
import 'package:veraprob/application/admin/user_management_command_service.dart';
import 'package:veraprob/application/admin/user_management_query_service.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/infrastructure/admin/postgres_user_management_query_service.dart';

class MockUserManagementCommandService extends Mock
    implements UserManagementCommandService {}

class MockUserManagementQueryService extends Mock
    implements PostgresUserManagementQueryService {}

void main() {
  late MockUserManagementCommandService commandService;
  late MockUserManagementQueryService queryService;
  late RemoveMemberHandler handler;

  setUp(() {
    commandService = MockUserManagementCommandService();
    queryService = MockUserManagementQueryService();
    handler = RemoveMemberHandler(
      commandService: commandService,
      queryService: queryService,
    );
  });

  RemoveMemberCommand makeCommand({
    UserRole role = UserRole.admin,
    String targetId = 'user-2',
  }) {
    return RemoveMemberCommand(
      organizationId: 'org-1',
      callerRole: role,
      targetUserId: targetId,
    );
  }

  group('RemoveMemberHandler', () {
    test('Rejeita não-admin (operator/auditor)', () async {
      expect(
        () => handler.handle(makeCommand(role: UserRole.operator)),
        throwsException,
      );
      expect(
        () => handler.handle(makeCommand(role: UserRole.auditor)),
        throwsException,
      );
    });

    test('Rejeita remoção do último admin', () async {
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
            (e) => e.toString().contains(
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

    test('Passa quando ≥ 1 admin restante', () async {
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

    test('Erro quando membro não encontrado', () async {
      when(() => queryService.getMembers()).thenAnswer((_) async => []);

      expect(
        () => handler.handle(makeCommand(targetId: 'ghost')),
        throwsException,
      );
    });
  });
}
