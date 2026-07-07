import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/admin/access_management_service.dart';

void main() {
  group('AccessManagement Helpers', () {
    const roleA = TenantRole(
      id: 'r1',
      name: 'Auditor',
      description: null,
      isSystem: false,
      grants: [
        RolePermissionGrant(permissionKey: 'read:a'),
        RolePermissionGrant(permissionKey: 'read:b'),
      ],
    );
    const roleB = TenantRole(
      id: 'r2',
      name: 'Operador',
      description: null,
      isSystem: false,
      grants: [
        RolePermissionGrant(permissionKey: 'read:a'),
        RolePermissionGrant(permissionKey: 'write:a'),
      ],
    );
    const roleC = TenantRole(
      id: 'r3',
      name: 'Validador',
      description: null,
      isSystem: false,
      grants: [
        RolePermissionGrant(permissionKey: 'read:a'),
        RolePermissionGrant(permissionKey: 'read:b'),
        RolePermissionGrant(permissionKey: 'write:a'),
      ],
    );

    const roleD = TenantRole(
      id: 'r4',
      name: 'Administrador',
      description: null,
      isSystem: true,
      grants: [
        RolePermissionGrant(permissionKey: 'read:a'),
        RolePermissionGrant(permissionKey: 'read:b'),
        RolePermissionGrant(permissionKey: 'write:a'),
      ],
    );

    final roles = [roleA, roleB, roleC, roleD];

    group('highestPrivilegeRoleName', () {
      test('returns null if no assignments', () {
        expect(
          highestPrivilegeRoleName(userId: 'u1', assignments: [], roles: roles),
          isNull,
        );
      });

      test('returns single role name', () {
        expect(
          highestPrivilegeRoleName(
            userId: 'u1',
            assignments: [
              const RoleAssignment(
                userId: 'u1',
                roleId: 'r1',
                validUntilUtc: null,
              ),
            ],
            roles: roles,
          ),
          'Auditor',
        );
      });

      test('returns role with most permissions', () {
        expect(
          highestPrivilegeRoleName(
            userId: 'u1',
            assignments: [
              const RoleAssignment(
                userId: 'u1',
                roleId: 'r1',
                validUntilUtc: null,
              ), // 2 keys
              const RoleAssignment(
                userId: 'u1',
                roleId: 'r3',
                validUntilUtc: null,
              ), // 3 keys
            ],
            roles: roles,
          ),
          'Validador',
        );
      });

      test(
        'deterministic tie-break (alphabetical) for same permission count',
        () {
          // roleC (Validador) and roleD (Administrador) both have 3 permissions.
          // Administrador should win alphabetically over Validador
          expect(
            highestPrivilegeRoleName(
              userId: 'u1',
              assignments: [
                const RoleAssignment(
                  userId: 'u1',
                  roleId: 'r3',
                  validUntilUtc: null,
                ),
                const RoleAssignment(
                  userId: 'u1',
                  roleId: 'r4',
                  validUntilUtc: null,
                ),
              ],
              roles: roles,
            ),
            'Administrador',
          );
        },
      );
    });

    group('memberHeldPermissionKeys', () {
      test('returns union of keys', () {
        expect(
          memberHeldPermissionKeys(
            userId: 'u1',
            assignments: [
              const RoleAssignment(
                userId: 'u1',
                roleId: 'r1',
                validUntilUtc: null,
              ),
              const RoleAssignment(
                userId: 'u1',
                roleId: 'r2',
                validUntilUtc: null,
              ),
            ],
            roles: roles,
          ),
          {'read:a', 'read:b', 'write:a'},
        );
      });

      test('returns empty set if no assignments', () {
        expect(
          memberHeldPermissionKeys(userId: 'u1', assignments: [], roles: roles),
          isEmpty,
        );
      });
    });
  });
}
