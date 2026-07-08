// user_management_screen_test.dart
//
// _MemberRolesRow (Pilar 3.1 multi-role):
// - Atribuição com valid_until renderiza chip Âmbar com a data de expiração.
// - Atribuição permanente mantém o tint primary, sem data.
//
// RBAC unificado em tenant roles (Palantir-tier):
// - Case 2: hierarquia de concessão/gestão espelha os guards de DB
//   (`_rbac_assert_can_grant_role` / `_rbac_assert_can_manage_target`) —
//   dropdown legado removido, chips/ações somem quando fora do teto do
//   chamador.
// - Case 3: badge do próprio usuário reflete o perfil real (nunca hardcoded).
// - Case 4: membros inativados migram para a seção "Arquivados" e podem ser
//   reativados.
// - Case 5: filtro de equipe por e-mail/perfil, client-side.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:veraprob/application/admin/access_management_service.dart';
import 'package:veraprob/application/admin/user_management_command_service.dart';
import 'package:veraprob/application/admin/user_management_query_service.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/admin/invitation.dart';
import 'package:veraprob/domain/services/permission_service.dart';
import 'package:veraprob/features/admin/presentation/screens/user_management_screen.dart';
import 'package:veraprob/state/providers/access_providers.dart';
import 'package:veraprob/state/providers/admin_providers.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/contract_providers.dart';

class MockUserManagementCommandService extends Mock
    implements UserManagementCommandService {}

class MockTenantValidationService extends Mock
    implements TenantValidationService {}

const _roles = <TenantRole>[
  TenantRole(
    id: 'role-1',
    name: 'Operador Logístico',
    description: null,
    isSystem: false,
    grants: [RolePermissionGrant(permissionKey: 'contracts:read')],
  ),
  TenantRole(
    id: 'role-2',
    name: 'Diretor Financeiro',
    description: null,
    isSystem: false,
    grants: [RolePermissionGrant(permissionKey: 'financial:read')],
  ),
];

Widget _wrap({required List<RoleAssignment> assignments}) {
  return ProviderScope(
    overrides: [
      currentUserRoleProvider.overrideWith((ref) => UserRole.admin),
      currentOperatorIdProvider.overrideWith((ref) => 'op-admin'),
      permissionServiceProvider.overrideWith(
        (ref) => const PermissionService(
          permissions: <String>{'roles:manage', 'users:manage'},
          scopes: <String, Set<String>>{},
        ),
      ),
      orgMembersProvider.overrideWith(
        (ref) => [
          OrgMember(
            userId: 'u1',
            email: 'membro@teste.com',
            role: UserRole.operator,
            invitedAt: DateTime.utc(2026, 1, 1, 12),
          ),
        ],
      ),
      orgInvitationsProvider.overrideWith((ref) => []),
      tenantRolesProvider.overrideWith((ref) => _roles),
      activeRoleAssignmentsProvider.overrideWith((ref) => assignments),
    ],
    child: const MaterialApp(home: Scaffold(body: UserManagementTab())),
  );
}

void main() {
  testWidgets(
    'atribuição com valid_until renderiza chip Âmbar com data de expiração',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          assignments: [
            // Meio-dia UTC: a data local não muda em fusos ±11h (sem flake).
            RoleAssignment(
              userId: 'u1',
              roleId: 'role-1',
              validUntilUtc: DateTime.utc(2026, 8, 1, 12),
            ),
            const RoleAssignment(
              userId: 'u1',
              roleId: 'role-2',
              validUntilUtc: null,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Chip com expiração: Âmbar + data + ícone de relógio.
      final expiringLabel = tester.widget<Text>(
        find.text('Operador Logístico · até 01/08/2026'),
      );
      expect(expiringLabel.style?.color, VeraProbColors.warning);
      expect(find.byIcon(Icons.schedule_outlined), findsOneWidget);

      // Chip permanente: sem data, cor padrão.
      final permanentLabel = tester.widget<Text>(
        find.text('Diretor Financeiro'),
      );
      expect(permanentLabel.style?.color, isNot(VeraProbColors.warning));
    },
  );

  testWidgets(
    'sem users:manage, o botão Convidar e as ações de inativação ficam ocultos',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserRoleProvider.overrideWith((ref) => UserRole.admin),
            currentOperatorIdProvider.overrideWith((ref) => 'op-admin'),
            permissionServiceProvider.overrideWith(
              (ref) => const PermissionService(
                // Apenas roles:read para que a aba carregue, mas sem users:manage
                permissions: <String>{'roles:read'},
                scopes: <String, Set<String>>{},
              ),
            ),
            orgMembersProvider.overrideWith(
              (ref) => [
                OrgMember(
                  userId: 'u1',
                  email: 'membro@teste.com',
                  role: UserRole.operator,
                  invitedAt: DateTime.utc(2026, 1, 1, 12),
                ),
              ],
            ),
            orgInvitationsProvider.overrideWith((ref) => []),
            tenantRolesProvider.overrideWith((ref) => _roles),
            activeRoleAssignmentsProvider.overrideWith((ref) => []),
          ],
          child: const MaterialApp(home: Scaffold(body: UserManagementTab())),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Convidar'), findsNothing);
      expect(find.byIcon(Icons.person_off_outlined), findsNothing);
      // O dropdown legado de UserRole não existe mais em lugar nenhum da tela
      // (profile unificado em tenant roles — case 2).
      expect(find.byType(DropdownButton<UserRole>), findsNothing);
      // Sem users:manage/roles:manage a linha de chips de perfil nem monta.
      expect(find.byType(ActionChip), findsNothing);
    },
  );

  group('Case 2 — hierarquia e guarda de escalonamento', () {
    const roleAdmin = TenantRole(
      id: 'role-admin',
      name: 'Administrador',
      description: null,
      isSystem: true,
      grants: [
        RolePermissionGrant(permissionKey: 'admin:only'),
        RolePermissionGrant(permissionKey: 'contracts:read'),
        RolePermissionGrant(permissionKey: 'financial:read'),
      ],
    );
    const roleValidador = TenantRole(
      id: 'role-validador',
      name: 'Validador',
      description: null,
      isSystem: false,
      grants: [
        RolePermissionGrant(permissionKey: 'contracts:read'),
        RolePermissionGrant(permissionKey: 'financial:read'),
      ],
    );
    const roleOperador = TenantRole(
      id: 'role-operador',
      name: 'Operador',
      description: null,
      isSystem: false,
      grants: [RolePermissionGrant(permissionKey: 'contracts:read')],
    );
    const hierarchyRoles = [roleAdmin, roleValidador, roleOperador];

    Widget wrapHierarchy({
      required Set<String> callerPermissions,
      required List<OrgMember> members,
      required List<RoleAssignment> assignments,
    }) {
      return ProviderScope(
        overrides: [
          currentUserRoleProvider.overrideWith((ref) => UserRole.operator),
          currentOperatorIdProvider.overrideWith((ref) => 'op-validador'),
          currentPermissionsProvider.overrideWith((ref) => callerPermissions),
          permissionServiceProvider.overrideWith(
            (ref) => PermissionService(
              permissions: callerPermissions,
              scopes: const <String, Set<String>>{},
            ),
          ),
          orgMembersProvider.overrideWith((ref) => members),
          orgInvitationsProvider.overrideWith((ref) => []),
          tenantRolesProvider.overrideWith((ref) => hierarchyRoles),
          activeRoleAssignmentsProvider.overrideWith((ref) => assignments),
        ],
        child: const MaterialApp(home: Scaffold(body: UserManagementTab())),
      );
    }

    testWidgets('membro que detém Administrador é view-only para um Validador '
        '(sem excluir chip, sem + Perfil)', (tester) async {
      await tester.pumpWidget(
        wrapHierarchy(
          callerPermissions: const {
            'contracts:read',
            'financial:read',
            'roles:manage',
            'users:manage',
          },
          members: [
            OrgMember(
              userId: 'op-validador',
              email: 'validador@teste.com',
              role: UserRole.operator,
              invitedAt: DateTime.utc(2026, 1, 1),
            ),
            OrgMember(
              userId: 'u-admin',
              email: 'admin@teste.com',
              role: UserRole.admin,
              invitedAt: DateTime.utc(2026, 1, 1),
            ),
          ],
          assignments: const [
            RoleAssignment(
              userId: 'op-validador',
              roleId: 'role-validador',
              validUntilUtc: null,
            ),
            // Self already holds every role within its own ceiling, so no
            // "+ Perfil" should render for it either — isolates the
            // assertion to the locked target's row.
            RoleAssignment(
              userId: 'op-validador',
              roleId: 'role-operador',
              validUntilUtc: null,
            ),
            RoleAssignment(
              userId: 'u-admin',
              roleId: 'role-admin',
              validUntilUtc: null,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final adminChipFinder = find.ancestor(
        of: find.text('Administrador'),
        matching: find.byType(Chip),
      );
      expect(adminChipFinder, findsOneWidget);
      final adminChip = tester.widget<Chip>(adminChipFinder);
      expect(adminChip.deleteIcon, isNull);
      expect(adminChip.onDeleted, isNull);

      // Nem o alvo (locked) nem o próprio Validador (ceiling já esgotado
      // pelas duas roles concedíveis) exibem "+ Perfil".
      expect(find.byType(ActionChip), findsNothing);
    });

    testWidgets(
      'Validador pode conceder Operador a um membro sem perfil (dentro do teto)',
      (tester) async {
        await tester.pumpWidget(
          wrapHierarchy(
            callerPermissions: const {
              'contracts:read',
              'financial:read',
              'roles:manage',
              'users:manage',
            },
            members: [
              OrgMember(
                userId: 'op-validador',
                email: 'validador@teste.com',
                role: UserRole.operator,
                invitedAt: DateTime.utc(2026, 1, 1),
              ),
              OrgMember(
                userId: 'u-plain',
                email: 'novo@teste.com',
                role: UserRole.operator,
                invitedAt: DateTime.utc(2026, 1, 1),
              ),
            ],
            assignments: const [
              RoleAssignment(
                userId: 'op-validador',
                roleId: 'role-validador',
                validUntilUtc: null,
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        // Abre o dialog de atribuição do membro sem perfil.
        await tester.tap(find.byType(ActionChip).last);
        await tester.pumpAndSettle();

        expect(find.text('Atribuir Perfil de Acesso'), findsOneWidget);
        // Administrador está fora do teto do Validador — nunca aparece.
        expect(find.text('Administrador'), findsNothing);

        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();
        expect(find.text('Operador'), findsWidgets);
        expect(find.text('Validador'), findsWidgets);
        expect(find.text('Administrador'), findsNothing);
      },
    );

    testWidgets(
      'diálogo de convite oculta Administrador para chamador sem "*"',
      (tester) async {
        await tester.pumpWidget(
          wrapHierarchy(
            callerPermissions: const {
              'contracts:read',
              'financial:read',
              'roles:manage',
              'users:manage',
            },
            members: const [],
            assignments: const [],
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Convidar'));
        await tester.pumpAndSettle();

        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();

        expect(find.text('Administrador'), findsNothing);
        expect(find.text('Operador'), findsWidgets);
        expect(find.text('Validador'), findsWidgets);
      },
    );

    testWidgets(
      'diálogo de convite exibe Administrador para chamador com "*"',
      (tester) async {
        await tester.pumpWidget(
          wrapHierarchy(
            callerPermissions: const {'*'},
            members: const [],
            assignments: const [],
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Convidar'));
        await tester.pumpAndSettle();

        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();

        expect(find.text('Administrador'), findsWidgets);
      },
    );
  });

  group('Case 3 — self-badge reflete o perfil real', () {
    testWidgets('Você · Validador substitui o hardcoded "Você (Admin)"', (
      tester,
    ) async {
      const roleValidador = TenantRole(
        id: 'role-validador',
        name: 'Validador',
        description: null,
        isSystem: false,
        grants: [RolePermissionGrant(permissionKey: 'contracts:read')],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserRoleProvider.overrideWith((ref) => UserRole.admin),
            currentOperatorIdProvider.overrideWith((ref) => 'op-admin'),
            currentPermissionsProvider.overrideWith(
              (ref) => const {'contracts:read'},
            ),
            permissionServiceProvider.overrideWith(
              (ref) => const PermissionService(
                permissions: <String>{'roles:manage', 'users:manage'},
                scopes: <String, Set<String>>{},
              ),
            ),
            orgMembersProvider.overrideWith(
              (ref) => [
                OrgMember(
                  userId: 'op-admin',
                  email: 'eu@teste.com',
                  role: UserRole.admin,
                  invitedAt: DateTime.utc(2026, 1, 1),
                ),
              ],
            ),
            orgInvitationsProvider.overrideWith((ref) => []),
            tenantRolesProvider.overrideWith((ref) => const [roleValidador]),
            activeRoleAssignmentsProvider.overrideWith(
              (ref) => const [
                RoleAssignment(
                  userId: 'op-admin',
                  roleId: 'role-validador',
                  validUntilUtc: null,
                ),
              ],
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: UserManagementTab())),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Você · Validador'), findsOneWidget);
      expect(find.textContaining('Admin)'), findsNothing);
    });

    testWidgets('sem perfil tenant, o self-badge cai no fallback coarse', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserRoleProvider.overrideWith((ref) => UserRole.admin),
            currentOperatorIdProvider.overrideWith((ref) => 'op-admin'),
            permissionServiceProvider.overrideWith(
              (ref) => const PermissionService(
                permissions: <String>{'roles:manage', 'users:manage'},
                scopes: <String, Set<String>>{},
              ),
            ),
            orgMembersProvider.overrideWith(
              (ref) => [
                OrgMember(
                  userId: 'op-admin',
                  email: 'eu@teste.com',
                  role: UserRole.admin,
                  invitedAt: DateTime.utc(2026, 1, 1),
                ),
              ],
            ),
            orgInvitationsProvider.overrideWith((ref) => []),
            tenantRolesProvider.overrideWith((ref) => const <TenantRole>[]),
            activeRoleAssignmentsProvider.overrideWith(
              (ref) => const <RoleAssignment>[],
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: UserManagementTab())),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Você · Administrador'), findsOneWidget);
    });
  });

  group('Case 4 — Arquivados + reativação', () {
    testWidgets('membro inativo some da lista ativa, aparece em Arquivados e '
        'Reativar aciona o handler + invalida a lista', (tester) async {
      final mockCommandService = MockUserManagementCommandService();
      final mockTenantValidator = MockTenantValidationService();
      when(
        () => mockTenantValidator.assertTenantMatches(
          payloadOrgId: any(named: 'payloadOrgId'),
          sessionId: any(named: 'sessionId'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => mockCommandService.reactivateMember(
          organizationId: any(named: 'organizationId'),
          targetUserId: any(named: 'targetUserId'),
        ),
      ).thenAnswer((_) async {});

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserRoleProvider.overrideWith((ref) => UserRole.admin),
            currentOperatorIdProvider.overrideWith((ref) => 'op-admin'),
            currentOrganizationIdProvider.overrideWith((ref) => 'org-1'),
            currentSessionIdProvider.overrideWith((ref) => 'session-1'),
            permissionServiceProvider.overrideWith(
              (ref) => const PermissionService(
                permissions: <String>{'roles:manage', 'users:manage'},
                scopes: <String, Set<String>>{},
              ),
            ),
            tenantValidationServiceProvider.overrideWith(
              (ref) => mockTenantValidator,
            ),
            userManagementCommandServiceProvider.overrideWith(
              (ref) => mockCommandService,
            ),
            orgMembersProvider.overrideWith(
              (ref) => [
                OrgMember(
                  userId: 'u1',
                  email: 'ativo@teste.com',
                  role: UserRole.operator,
                  invitedAt: DateTime.utc(2026, 1, 1),
                ),
                OrgMember(
                  userId: 'u2',
                  email: 'arquivado@teste.com',
                  role: UserRole.operator,
                  invitedAt: DateTime.utc(2026, 1, 1),
                  isActive: false,
                ),
              ],
            ),
            orgInvitationsProvider.overrideWith((ref) => []),
            tenantRolesProvider.overrideWith((ref) => const <TenantRole>[]),
            activeRoleAssignmentsProvider.overrideWith(
              (ref) => const <RoleAssignment>[],
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: UserManagementTab())),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('ativo@teste.com'), findsOneWidget);
      expect(find.text('Arquivados (1)'), findsOneWidget);
      expect(find.text('arquivado@teste.com'), findsOneWidget);
      expect(find.text('Reativar'), findsOneWidget);

      await tester.tap(find.text('Reativar'));
      await tester.pumpAndSettle();
      expect(find.text('Reativar Membro'), findsOneWidget);

      await tester.tap(find.text('Reativar').last);
      await tester.pumpAndSettle();

      verify(
        () => mockCommandService.reactivateMember(
          organizationId: 'org-1',
          targetUserId: 'u2',
        ),
      ).called(1);
      expect(find.text('Membro reativado com sucesso.'), findsOneWidget);
    });
  });

  group('Case 5 — filtro de equipe (e-mail + perfil)', () {
    const roleValidador = TenantRole(
      id: 'role-validador',
      name: 'Validador',
      description: null,
      isSystem: false,
      grants: [RolePermissionGrant(permissionKey: 'contracts:read')],
    );
    const roleOperador = TenantRole(
      id: 'role-operador',
      name: 'Operador',
      description: null,
      isSystem: false,
      grants: [RolePermissionGrant(permissionKey: 'financial:read')],
    );

    Widget wrapFilter() {
      return ProviderScope(
        overrides: [
          currentUserRoleProvider.overrideWith((ref) => UserRole.admin),
          currentOperatorIdProvider.overrideWith((ref) => 'op-admin'),
          permissionServiceProvider.overrideWith(
            (ref) => const PermissionService(
              permissions: <String>{'roles:manage', 'users:manage'},
              scopes: <String, Set<String>>{},
            ),
          ),
          orgMembersProvider.overrideWith(
            (ref) => [
              OrgMember(
                userId: 'u-alice',
                email: 'alice@teste.com',
                role: UserRole.operator,
                invitedAt: DateTime.utc(2026, 1, 1),
              ),
              OrgMember(
                userId: 'u-bob',
                email: 'bob@teste.com',
                role: UserRole.operator,
                invitedAt: DateTime.utc(2026, 1, 1),
              ),
            ],
          ),
          orgInvitationsProvider.overrideWith((ref) => []),
          tenantRolesProvider.overrideWith(
            (ref) => const [roleValidador, roleOperador],
          ),
          activeRoleAssignmentsProvider.overrideWith(
            (ref) => const [
              RoleAssignment(
                userId: 'u-alice',
                roleId: 'role-validador',
                validUntilUtc: null,
              ),
              RoleAssignment(
                userId: 'u-bob',
                roleId: 'role-operador',
                validUntilUtc: null,
              ),
            ],
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: UserManagementTab())),
      );
    }

    testWidgets('filtro por e-mail restringe a lista', (tester) async {
      await tester.pumpWidget(wrapFilter());
      await tester.pumpAndSettle();

      expect(find.text('alice@teste.com'), findsOneWidget);
      expect(find.text('bob@teste.com'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'alice');
      await tester.pumpAndSettle();

      expect(find.text('alice@teste.com'), findsOneWidget);
      expect(find.text('bob@teste.com'), findsNothing);

      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();

      expect(find.text('alice@teste.com'), findsOneWidget);
      expect(find.text('bob@teste.com'), findsOneWidget);
    });

    testWidgets('filtro por perfil restringe a lista', (tester) async {
      await tester.pumpWidget(wrapFilter());
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Validador').last);
      await tester.pumpAndSettle();

      expect(find.text('alice@teste.com'), findsOneWidget);
      expect(find.text('bob@teste.com'), findsNothing);

      await tester.tap(find.byType(DropdownButtonFormField<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Todos').last);
      await tester.pumpAndSettle();

      expect(find.text('alice@teste.com'), findsOneWidget);
      expect(find.text('bob@teste.com'), findsOneWidget);
    });
  });

  group('Case 6 — Filtro por status e ações de convite', () {
    Widget wrapStatusFilter() {
      return ProviderScope(
        overrides: [
          currentUserRoleProvider.overrideWith((ref) => UserRole.admin),
          currentOperatorIdProvider.overrideWith((ref) => 'op-admin'),
          permissionServiceProvider.overrideWith(
            (ref) => const PermissionService(
              permissions: <String>{'roles:manage', 'users:manage'},
              scopes: <String, Set<String>>{},
            ),
          ),
          orgMembersProvider.overrideWith(
            (ref) => [
              OrgMember(
                userId: 'u-alice',
                email: 'alice-active@teste.com',
                role: UserRole.operator,
                invitedAt: DateTime.utc(2026, 1, 1),
              ),
              OrgMember(
                userId: 'u-bob',
                email: 'bob-archived@teste.com',
                role: UserRole.operator,
                invitedAt: DateTime.utc(2026, 1, 1),
                isActive: false,
              ),
            ],
          ),
          orgInvitationsProvider.overrideWith(
            (ref) => [
              Invitation(
                id: 'inv-1',
                organizationId: 'org-1',
                email: 'pending@teste.com',
                role: UserRole.operator,
                token: 'tok-123',
                invitedBy: 'u-admin',
                createdAtUtc: DateTime.utc(2026, 1, 1),
                expiresAtUtc: DateTime.utc(2030, 1, 1),
              ),
            ],
          ),
          tenantRolesProvider.overrideWith((ref) => const []),
          activeRoleAssignmentsProvider.overrideWith((ref) => const []),
        ],
        child: const MaterialApp(home: Scaffold(body: UserManagementTab())),
      );
    }

    testWidgets('renderiza 3 botões de ação no convite pendente', (
      tester,
    ) async {
      await tester.pumpWidget(wrapStatusFilter());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.copy_outlined), findsOneWidget);
      expect(find.byIcon(Icons.send_outlined), findsOneWidget);
      expect(find.byIcon(Icons.cancel_outlined), findsOneWidget);
    });

    testWidgets(
      'filtro status=pending oculta ativos e arquivados e mostra convites',
      (tester) async {
        await tester.pumpWidget(wrapStatusFilter());
        await tester.pumpAndSettle();
        await tester.tap(find.text('Todos').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Convite Pendente').last);
        await tester.pumpAndSettle();

        expect(find.text('alice-active@teste.com'), findsNothing);
        expect(find.text('bob-archived@teste.com'), findsNothing);
        expect(find.text('pending@teste.com'), findsOneWidget);
      },
    );

    testWidgets('filtro status=active oculta convites e arquivados', (
      tester,
    ) async {
      await tester.pumpWidget(wrapStatusFilter());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Todos').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ativo').last);
      await tester.pumpAndSettle();

      expect(find.text('alice-active@teste.com'), findsOneWidget);
      expect(find.text('bob-archived@teste.com'), findsNothing);
      expect(find.text('pending@teste.com'), findsNothing);
    });

    testWidgets('filtro status=archived mostra apenas arquivados', (
      tester,
    ) async {
      await tester.pumpWidget(wrapStatusFilter());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Todos').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Arquivado').last);
      await tester.pumpAndSettle();

      expect(find.text('alice-active@teste.com'), findsNothing);
      expect(find.text('bob-archived@teste.com'), findsOneWidget);
      expect(find.text('pending@teste.com'), findsNothing);
    });
  });
}
