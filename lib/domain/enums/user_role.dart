/// Defines the hierarchical roles within the BusFlow operational environment.
///
/// This forms the basis of the RBAC (Role-Based Access Control) system,
/// dictating which UI elements and mutation actions a user can perform.
enum UserRole {
  /// Top-level access. Can configure system parameters, delete critical records (like Drivers or Vehicles).
  admin,

  /// Mid-level access. Can create incidents, dispatch vehicles, and resolve alerts.
  supervisor,

  /// Base-level access. Can only view the map, alerts, and perform basic trip reporting.
  operator;

  /// Returns true if this role has equal or greater privileges than the [requiredRole].
  bool hasPermission(UserRole requiredRole) {
    switch (requiredRole) {
      case UserRole.operator:
        return this == UserRole.admin ||
            this == UserRole.supervisor ||
            this == UserRole.operator;
      case UserRole.supervisor:
        return this == UserRole.admin || this == UserRole.supervisor;
      case UserRole.admin:
        return this == UserRole.admin;
    }
  }

  /// Human-readable label for UI display.
  String get label {
    switch (this) {
      case UserRole.admin:
        return 'Administrador';
      case UserRole.supervisor:
        return 'Supervisor';
      case UserRole.operator:
        return 'Operador';
    }
  }
}
