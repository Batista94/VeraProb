import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/admin/access_management_service.dart';

void main() {
  group('RolePermissionGrant.toJson', () {
    test('unrestricted grant omits the scope key', () {
      const grant = RolePermissionGrant(permissionKey: 'financial:read');
      expect(grant.toJson(), <String, Object?>{'key': 'financial:read'});
      expect(grant.toJson().containsKey('scope'), isFalse);
    });

    test('scoped grant serializes contract_ids allowlist', () {
      const grant = RolePermissionGrant(
        permissionKey: 'financial:read',
        contractScopeIds: {'c-1', 'c-2'},
      );
      final json = grant.toJson();
      expect(json['key'], 'financial:read');
      final scope = json['scope'] as Map<String, Object?>;
      expect(scope['contract_ids'], containsAll(<String>['c-1', 'c-2']));
    });
  });

  group('TenantRole.permissionKeys', () {
    test('collects the granted keys', () {
      const role = TenantRole(
        id: 'r1',
        name: 'Op',
        description: null,
        isSystem: false,
        grants: [
          RolePermissionGrant(permissionKey: 'financial:read'),
          RolePermissionGrant(permissionKey: 'sla:read'),
        ],
      );
      expect(role.permissionKeys, {'financial:read', 'sla:read'});
    });
  });

  group('RoleAssignment.isActiveAt', () {
    final now = DateTime.utc(2026, 7, 4);

    test('permanent (null valid_until) is always active', () {
      const a = RoleAssignment(userId: 'u', roleId: 'r', validUntilUtc: null);
      expect(a.isActiveAt(now), isTrue);
    });

    test('future expiry is active, past expiry is not', () {
      final future = RoleAssignment(
        userId: 'u',
        roleId: 'r',
        validUntilUtc: now.add(const Duration(days: 1)),
      );
      final past = RoleAssignment(
        userId: 'u',
        roleId: 'r',
        validUntilUtc: now.subtract(const Duration(days: 1)),
      );
      expect(future.isActiveAt(now), isTrue);
      expect(past.isActiveAt(now), isFalse);
    });
  });

  group('RoleChangeRequest.proposedPermissionKeys', () {
    test('extracts keys from a perm_grants payload', () {
      final req = RoleChangeRequest(
        id: 'req',
        requestType: 'UPDATE_ROLE_PERMISSIONS',
        requestedBy: 'admin',
        payload: const {
          'perm_grants': [
            {'key': 'financial:read'},
            {'key': 'financial:export'},
          ],
        },
        createdAtUtc: DateTime.utc(2026, 7, 1),
      );
      expect(req.proposedPermissionKeys, [
        'financial:read',
        'financial:export',
      ]);
    });

    test('GRANT_ROLE payload without perm_grants yields no keys', () {
      final req = RoleChangeRequest(
        id: 'req',
        requestType: 'GRANT_ROLE',
        requestedBy: 'admin',
        payload: const {'target_user': 'u', 'role_id': 'r'},
        createdAtUtc: DateTime.utc(2026, 7, 1),
      );
      expect(req.proposedPermissionKeys, isEmpty);
    });
  });
}
