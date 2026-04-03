/// Defines the hierarchical roles within the veraprob operational environment.
///
/// This forms the basis of the RBAC (Role-Based Access Control) system,
/// dictating which UI elements and mutation actions a user can perform.
enum UserRole {
  /// Top-level access. Can configure organization settings, invite users, and edit SLA rules.
  admin,

  /// Mid-level access. Can create contracts, zones, and declare operational plans.
  operator,

  /// Read-only access. Can view dashboards, reports, and audit trails.
  auditor,

  /// External contractor read-only access. Scoped to a single contractor via
  /// dual-key JWT isolation (INV-20). Cannot access any tenant-internal information.
  /// JWT carries both org_id and contractor_id claims.
  contractorViewer,

  /// Platform-level super administrator. Cross-tenant access via service_role.
  /// JWT carries `super_admin: true` and null org_id/role/contractor_id (D2).
  /// Never mixed with tenant roles — stored in `super_admin_users` (D1).
  superAdmin;

  /// Returns true if this role has equal or greater privileges than the [requiredRole].
  ///
  /// [contractorViewer] has no privileges in the tenant-internal hierarchy —
  /// it operates in a separate, contractor-scoped access domain.
  bool hasPermission(UserRole requiredRole) {
    if (this == UserRole.contractorViewer) return false;
    if (this == UserRole.superAdmin) {
      return true; // superAdmin has all permissions
    }
    if (this == UserRole.admin) return true;
    if (this == UserRole.operator) {
      return requiredRole == UserRole.operator ||
          requiredRole == UserRole.auditor;
    }
    return requiredRole == UserRole.auditor;
  }

  /// Human-readable label for UI display.
  String get label {
    switch (this) {
      case UserRole.admin:
        return 'Administrador';
      case UserRole.operator:
        return 'Operador';
      case UserRole.auditor:
        return 'Auditor';
      case UserRole.contractorViewer:
        return 'Visualizador Contratante';
      case UserRole.superAdmin:
        return 'Super Administrador';
    }
  }
}
