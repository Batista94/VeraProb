/// Defines the hierarchical roles within the PactaFlow operational environment.
///
/// This forms the basis of the RBAC (Role-Based Access Control) system,
/// dictating which UI elements and mutation actions a user can perform.
enum UserRole {
  /// Top-level access. Can configure organization settings, invite users, and edit SLA rules.
  admin,

  /// Mid-level access. Can create contracts, zones, and declare operational plans.
  operator,

  /// Read-only access. Can view dashboards, reports, and audit trails.
  auditor;

  /// Returns true if this role has equal or greater privileges than the [requiredRole].
  bool hasPermission(UserRole requiredRole) {
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
    }
  }
}
