import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/infrastructure/admin/postgres_access_management_service.dart';

/// Pure row → DTO parsing (the non-trivial part: embedded grants + scope jsonb +
/// UTC date coercion). The transport (Supabase query builder) is exercised by
/// integration/E2E, not mocked here.
void main() {
  group('parseRole', () {
    test('parses embedded grants and scope allowlist', () {
      final role = PostgresAccessManagementService.parseRole({
        'id': 'r1',
        'name': 'Operador',
        'description': 'op',
        'is_system': false,
        'tenant_role_permissions': [
          {'permission_key': 'financial:read', 'scope': null},
          {
            'permission_key': 'contracts:read',
            'scope': {
              'contract_ids': ['c-1', 'c-2'],
            },
          },
        ],
      });

      expect(role.id, 'r1');
      expect(role.isSystem, isFalse);
      expect(role.permissionKeys, {'financial:read', 'contracts:read'});
      final scoped = role.grants.firstWhere(
        (g) => g.permissionKey == 'contracts:read',
      );
      expect(scoped.contractScopeIds, {'c-1', 'c-2'});
      final unscoped = role.grants.firstWhere(
        (g) => g.permissionKey == 'financial:read',
      );
      expect(unscoped.contractScopeIds, isEmpty);
    });

    test('missing tenant_role_permissions yields no grants', () {
      final role = PostgresAccessManagementService.parseRole({
        'id': 'r2',
        'name': 'Vazio',
        'description': null,
        'is_system': true,
      });
      expect(role.grants, isEmpty);
      expect(role.isSystem, isTrue);
    });
  });

  group('parseAssignment', () {
    test('null valid_until = permanent', () {
      final a = PostgresAccessManagementService.parseAssignment({
        'user_id': 'u1',
        'tenant_role_id': 'r1',
        'valid_until': null,
      });
      expect(a.validUntilUtc, isNull);
    });

    test('valid_until is coerced to UTC', () {
      final a = PostgresAccessManagementService.parseAssignment({
        'user_id': 'u1',
        'tenant_role_id': 'r1',
        'valid_until': '2026-08-01T12:00:00+00:00',
      });
      expect(a.validUntilUtc!.isUtc, isTrue);
      expect(a.validUntilUtc, DateTime.utc(2026, 8, 1, 12));
    });
  });

  group('parseRequest', () {
    test('parses a four-eyes request payload', () {
      final req = PostgresAccessManagementService.parseRequest({
        'id': 'req-1',
        'request_type': 'UPDATE_ROLE_PERMISSIONS',
        'requested_by': 'admin-1',
        'payload': {
          'role_id': 'r1',
          'perm_grants': [
            {'key': 'sla:approve'},
          ],
        },
        'created_at': '2026-07-01T00:00:00Z',
      });
      expect(req.requestType, 'UPDATE_ROLE_PERMISSIONS');
      expect(req.proposedPermissionKeys, ['sla:approve']);
      expect(req.createdAtUtc.isUtc, isTrue);
    });
  });

  group('parsePermission', () {
    test('maps dictionary flags', () {
      final p = PostgresAccessManagementService.parsePermission({
        'key': 'financial:export',
        'module': 'financial',
        'action': 'export',
        'label_pt': 'Exportar financeiro',
        'description': null,
        'is_sensitive': true,
        'is_scopable': false,
      });
      expect(p.isSensitive, isTrue);
      expect(p.isScopable, isFalse);
      expect(p.description, '');
    });
  });
}
