import 'package:veraprob/domain/enums/user_role.dart';

/// Immutable value object representing an authenticated user in the domain.
///
/// Pure Dart entity — zero infrastructure dependencies ([INV-18]).
/// The [tenantId] is guaranteed to come from trusted `app_metadata` claims
/// (injected by `custom_access_token_hook`), never from client-editable
/// `user_metadata`.
///
/// [email] is nullable to support phone-based and OAuth social logins where
/// email may not be present.
///
/// Future-proof: [isMfaEnabled] placeholder for MFA awareness expansion.
class AuthUser {
  final String id;
  final String? email;
  final String tenantId;
  final UserRole? role;
  final bool isMfaEnabled;

  const AuthUser({
    required this.id,
    this.email,
    required this.tenantId,
    this.role,
    this.isMfaEnabled = false,
  });

  /// Returns true if the user has a verified email address.
  bool get hasEmail => email != null && email!.isNotEmpty;

  /// Display name for UI: email if available, otherwise masked ID.
  String get displayName => email ?? id.substring(0, 8);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AuthUser &&
        other.id == id &&
        other.email == email &&
        other.tenantId == tenantId &&
        other.role == role &&
        other.isMfaEnabled == isMfaEnabled;
  }

  @override
  int get hashCode => Object.hash(id, email, tenantId, role, isMfaEnabled);

  @override
  String toString() =>
      'AuthUser(id: $id, email: $email, tenantId: $tenantId, '
      'role: $role, isMfaEnabled: $isMfaEnabled)';
}
