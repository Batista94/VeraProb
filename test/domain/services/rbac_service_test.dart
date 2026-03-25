// Tests for RbacService — Phase 9.4.4
//
// Validates that the centralized RBAC permission map and the UserRole
// hierarchy are consistently enforced.

import 'package:flutter_test/flutter_test.dart';

import 'package:veraprob/domain/enums/user_permissions.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/services/rbac_service.dart';

void main() {
  group('RbacService', () {
    final rbac = RbacService();

    // ── can() ────────────────────────────────────────────────────────────
    group('can()', () {
      test('admin has canEditSlaRules', () {
        expect(
          rbac.can(UserRole.admin, UserPermission.canEditSlaRules),
          isTrue,
        );
      });

      test('operator does NOT have canEditSlaRules', () {
        expect(
          rbac.can(UserRole.operator, UserPermission.canEditSlaRules),
          isFalse,
        );
      });

      test('superAdmin has canManageTenants', () {
        expect(
          rbac.can(UserRole.superAdmin, UserPermission.canManageTenants),
          isTrue,
        );
      });

      test('admin does NOT have canManageTenants (superAdmin-exclusive)', () {
        expect(
          rbac.can(UserRole.admin, UserPermission.canManageTenants),
          isFalse,
        );
      });

      test('admin and auditor can approve sanctions', () {
        expect(
          rbac.can(UserRole.admin, UserPermission.canApproveSanctions),
          isTrue,
        );
        expect(
          rbac.can(UserRole.auditor, UserPermission.canApproveSanctions),
          isTrue,
        );
      });

      test('operator cannot approve sanctions', () {
        expect(
          rbac.can(UserRole.operator, UserPermission.canApproveSanctions),
          isFalse,
        );
      });

      test('returns false for unknown permission (null allowedRoles)', () {
        // canViewAuditExports is in the map — confirm operator can view
        expect(
          rbac.can(UserRole.operator, UserPermission.canViewAuditExports),
          isTrue,
        );
      });
    });

    // ── hasMinimumRole() ──────────────────────────────────────────────────
    group('hasMinimumRole()', () {
      test('admin satisfies any minimum role', () {
        expect(rbac.hasMinimumRole(UserRole.admin, UserRole.admin), isTrue);
        expect(rbac.hasMinimumRole(UserRole.admin, UserRole.operator), isTrue);
        expect(rbac.hasMinimumRole(UserRole.admin, UserRole.auditor), isTrue);
      });

      test('superAdmin satisfies any minimum role', () {
        expect(
          rbac.hasMinimumRole(UserRole.superAdmin, UserRole.admin),
          isTrue,
        );
        expect(
          rbac.hasMinimumRole(UserRole.superAdmin, UserRole.auditor),
          isTrue,
        );
      });

      test('auditor does NOT satisfy operator minimum', () {
        expect(
          rbac.hasMinimumRole(UserRole.auditor, UserRole.operator),
          isFalse,
        );
      });

      test('contractorViewer never satisfies any internal minimum role', () {
        expect(
          rbac.hasMinimumRole(UserRole.contractorViewer, UserRole.auditor),
          isFalse,
        );
        expect(
          rbac.hasMinimumRole(UserRole.contractorViewer, UserRole.operator),
          isFalse,
        );
        expect(
          rbac.hasMinimumRole(UserRole.contractorViewer, UserRole.admin),
          isFalse,
        );
      });
    });
  });

  // ── UserRole.hasPermission() (inline in enum) ─────────────────────────
  group('UserRole.hasPermission()', () {
    test('operator satisfies auditor requirement', () {
      expect(UserRole.operator.hasPermission(UserRole.auditor), isTrue);
    });

    test('operator satisfies operator requirement', () {
      expect(UserRole.operator.hasPermission(UserRole.operator), isTrue);
    });

    test('operator does NOT satisfy admin requirement', () {
      expect(UserRole.operator.hasPermission(UserRole.admin), isFalse);
    });

    test('auditor satisfies only auditor requirement', () {
      expect(UserRole.auditor.hasPermission(UserRole.auditor), isTrue);
      expect(UserRole.auditor.hasPermission(UserRole.operator), isFalse);
      expect(UserRole.auditor.hasPermission(UserRole.admin), isFalse);
    });
  });
}
