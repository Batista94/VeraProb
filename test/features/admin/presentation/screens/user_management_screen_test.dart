// user_management_screen_test.dart
//
// _MemberRolesRow (Pilar 3.1 multi-role):
// - Atribuição com valid_until renderiza chip Âmbar com a data de expiração.
// - Atribuição permanente mantém o tint primary, sem data.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veraprob/application/admin/access_management_service.dart';
import 'package:veraprob/application/admin/user_management_query_service.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/services/permission_service.dart';
import 'package:veraprob/features/admin/presentation/screens/user_management_screen.dart';
import 'package:veraprob/state/providers/access_providers.dart';
import 'package:veraprob/state/providers/admin_providers.dart';
import 'package:veraprob/state/providers/auth_providers.dart';

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
          permissions: <String>{'roles:manage'},
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
}
