import 'package:veraprob/domain/enums/user_permissions.dart';
import 'package:veraprob/domain/enums/user_role.dart';

/// Pure logic service for Role-Based Access Control.
class RbacService {
  /// Returns true if the given [role] has the specified [permission].
  bool can(UserRole role, UserPermission permission) {
    final allowedRoles = rolePermissions[permission];
    if (allowedRoles == null) return false;
    return allowedRoles.contains(role);
  }

  /// Returns true if the given [role] meets the [minimumRole] requirement.
  bool hasMinimumRole(UserRole role, UserRole minimumRole) {
    return role.hasPermission(minimumRole);
  }
}
