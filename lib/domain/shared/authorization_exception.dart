/// Exception thrown when a user attempts an action their role does not permit.
///
/// Distinct from [DomainException] to enable precise error handling:
/// - [DomainException] = business rule violation (data-level).
/// - [AuthorizationException] = authority violation (policy-level).
///
/// The caller's [role] and the [requiredPermission] are sealed into the
/// exception for forensic traceability — the Red Team auditor can verify
/// exactly which authority was insufficient.
class AuthorizationException implements Exception {
  final String message;

  /// The role that was presented.
  final String? role;

  /// The permission or action that was required.
  final String? requiredPermission;

  const AuthorizationException(
    this.message, {
    this.role,
    this.requiredPermission,
  });

  @override
  String toString() =>
      'AuthorizationException: $message'
      '${role != null ? ' (role: $role)' : ''}'
      '${requiredPermission != null ? ' (required: $requiredPermission)' : ''}';
}
