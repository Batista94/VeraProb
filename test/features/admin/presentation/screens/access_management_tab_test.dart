// access_management_tab_test.dart
//
// Comportamento da fila four-eyes (Aprovações Pendentes):
// - Diff da solicitação: adições em Emerald (+), remoções em Red (−), com
//   label_pt resolvido do dicionário.
// - Solicitação própria: "Aguardando outro administrador" sem botões de ação.
// - CREATE_ROLE: tudo é adição, título carrega o nome proposto.
// - GRANT_ROLE: sem chips de diff, título resolve o nome do perfil.
// Goldens ficam em access_management_tab_golden_test.dart.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veraprob/application/admin/access_management_service.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/domain/services/permission_service.dart';
import 'package:veraprob/features/admin/presentation/screens/access_management_tab.dart';
import 'package:veraprob/state/providers/access_providers.dart';
import 'package:veraprob/state/providers/auth_providers.dart';

const _me = 'op-1';

const _dictionary = <TenantPermission>[
  TenantPermission(
    key: 'financial:read',
    module: 'financial',
    action: 'read',
    labelPt: 'Ler financeiro',
    description: 'Visualizar dados financeiros do tenant',
    isSensitive: false,
    isScopable: true,
  ),
  TenantPermission(
    key: 'financial:export',
    module: 'financial',
    action: 'export',
    labelPt: 'Exportar financeiro',
    description: 'Exportar relatórios financeiros (ação sensível)',
    isSensitive: true,
    isScopable: false,
  ),
  TenantPermission(
    key: 'sla:approve',
    module: 'sla',
    action: 'approve',
    labelPt: 'Aprovar sanções',
    description: 'Aprovar ou rejeitar sanções (ação sensível)',
    isSensitive: true,
    isScopable: false,
  ),
];

const _roles = <TenantRole>[
  TenantRole(
    id: 'role-1',
    name: 'Operador Logístico',
    description: 'Operação diária',
    isSystem: false,
    grants: [RolePermissionGrant(permissionKey: 'financial:read')],
  ),
  TenantRole(
    id: 'role-2',
    name: 'Diretor Financeiro',
    description: null,
    isSystem: true,
    grants: [
      RolePermissionGrant(permissionKey: 'financial:read'),
      RolePermissionGrant(permissionKey: 'financial:export'),
    ],
  ),
];

Widget _wrap({required List<RoleChangeRequest> pending}) {
  return ProviderScope(
    overrides: [
      permissionServiceProvider.overrideWith(
        (ref) => const PermissionService(
          permissions: <String>{'*'},
          scopes: <String, Set<String>>{},
        ),
      ),
      currentOperatorIdProvider.overrideWith((ref) => _me),
      permissionDictionaryProvider.overrideWith((ref) => _dictionary),
      tenantRolesProvider.overrideWith((ref) => _roles),
      activeRoleAssignmentsProvider.overrideWith(
        (ref) => const <RoleAssignment>[],
      ),
      pendingRoleChangesProvider.overrideWith((ref) => pending),
    ],
    child: const MaterialApp(home: Scaffold(body: AccessManagementTab())),
  );
}

void main() {
  testWidgets(
    'UPDATE_ROLE_PERMISSIONS renderiza diff: adição em Emerald, remoção em Red',
    (tester) async {
      // role-1 hoje tem financial:read; a proposta troca por financial:export.
      await tester.pumpWidget(
        _wrap(
          pending: [
            RoleChangeRequest(
              id: 'req-1',
              requestType: 'UPDATE_ROLE_PERMISSIONS',
              requestedBy: 'someone-else',
              payload: const {
                'role_id': 'role-1',
                'perm_grants': [
                  {'key': 'financial:export'},
                ],
              },
              // Meio-dia UTC: a data local não muda em fusos ±11h (sem flake).
              createdAtUtc: DateTime.utc(2026, 7, 1, 12),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Aprovações Pendentes (1)'), findsOneWidget);
      expect(
        find.text('Atualizar permissões · Operador Logístico'),
        findsOneWidget,
      );

      final added = tester.widget<Text>(find.text('+ Exportar financeiro'));
      expect(added.style?.color, VeraProbColors.success);

      final removed = tester.widget<Text>(find.text('− Ler financeiro'));
      expect(removed.style?.color, VeraProbColors.error);

      expect(find.text('Aprovar'), findsOneWidget);
      expect(find.text('Rejeitar'), findsOneWidget);
      expect(find.text('Solicitado em 01/07/2026'), findsOneWidget);
    },
  );

  testWidgets(
    'solicitação própria mostra "Aguardando outro administrador" sem ações',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          pending: [
            RoleChangeRequest(
              id: 'req-2',
              requestType: 'UPDATE_ROLE_PERMISSIONS',
              requestedBy: _me,
              payload: const {
                'role_id': 'role-1',
                'perm_grants': [
                  {'key': 'sla:approve'},
                ],
              },
              createdAtUtc: DateTime.utc(2026, 7, 2, 12),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Aguardando outro administrador'), findsOneWidget);
      expect(find.text('Aprovar'), findsNothing);
      expect(find.text('Rejeitar'), findsNothing);
    },
  );

  testWidgets(
    'CREATE_ROLE mostra o nome proposto e todas as chaves como adição',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          pending: [
            RoleChangeRequest(
              id: 'req-3',
              requestType: 'CREATE_ROLE',
              requestedBy: 'someone-else',
              payload: const {
                'name': 'Auditor Externo',
                'perm_grants': [
                  {'key': 'sla:approve'},
                  {'key': 'financial:read'},
                ],
              },
              createdAtUtc: DateTime.utc(2026, 7, 3, 12),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Novo perfil · Auditor Externo'), findsOneWidget);
      expect(find.text('+ Aprovar sanções'), findsOneWidget);
      expect(find.text('+ Ler financeiro'), findsOneWidget);
      expect(find.textContaining('−'), findsNothing);
    },
  );

  testWidgets('GRANT_ROLE resolve o nome do perfil e não renderiza diff', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        pending: [
          RoleChangeRequest(
            id: 'req-4',
            requestType: 'GRANT_ROLE',
            requestedBy: 'someone-else',
            payload: const {'role_id': 'role-2', 'target_user': 'u9'},
            createdAtUtc: DateTime.utc(2026, 7, 4, 12),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Atribuir perfil · Diretor Financeiro'), findsOneWidget);
    expect(find.textContaining('+ '), findsNothing);
    expect(find.textContaining('− '), findsNothing);
  });
}
