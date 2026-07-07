import 'package:alchemist/alchemist.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veraprob/application/admin/access_management_service.dart';
import 'package:veraprob/domain/services/permission_service.dart';
import 'package:veraprob/features/admin/presentation/screens/access_management_tab.dart';
import 'package:veraprob/state/providers/access_providers.dart';
import 'package:veraprob/state/providers/auth_providers.dart';

const _dictionary = <TenantPermission>[
  TenantPermission(
    key: 'financial:read',
    module: 'financial',
    action: 'read',
    labelPt: 'Ler financeiro',
    description: 'Visualizar dados financeiros da organização',
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

Widget _wrap(Widget child) {
  return ProviderScope(
    overrides: [
      permissionServiceProvider.overrideWith(
        (ref) => const PermissionService(
          permissions: <String>{'*'},
          scopes: <String, Set<String>>{},
        ),
      ),
      currentOperatorIdProvider.overrideWith((ref) => 'op-1'),
      permissionDictionaryProvider.overrideWith((ref) => _dictionary),
      tenantRolesProvider.overrideWith((ref) => _roles),
      activeRoleAssignmentsProvider.overrideWith(
        (ref) => const [
          RoleAssignment(userId: 'u1', roleId: 'role-1', validUntilUtc: null),
          RoleAssignment(userId: 'u2', roleId: 'role-1', validUntilUtc: null),
        ],
      ),
      pendingRoleChangesProvider.overrideWith(
        (ref) => [
          RoleChangeRequest(
            id: 'req-1',
            requestType: 'UPDATE_ROLE_PERMISSIONS',
            requestedBy: 'someone-else',
            payload: const {
              'perm_grants': [
                {'key': 'sla:approve'},
              ],
            },
            createdAtUtc: DateTime.utc(2026, 7, 1),
          ),
        ],
      ),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  group('AccessManagementTab Goldens (GOLDEN-UNWIRED)', () {
    goldenTest(
      'golden test — access management catalog (desktop)',
      fileName: 'access_management_tab_catalog',
      builder: () => SizedBox(
        width: 1024,
        height: 768,
        child: _wrap(const AccessManagementTab()),
      ),
      pumpBeforeTest: (tester) async {
        await tester.pumpAndSettle();
      },
    );
  });
}
