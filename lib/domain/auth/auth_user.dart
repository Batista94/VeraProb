import 'package:veraprob/domain/admin/actor_type.dart';
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

  // Phase 10.2: Impersonation context
  final ActorType? actorType;
  final String? impersonatorId;
  final DateTime? impersonationExpiresAt;

  const AuthUser({
    required this.id,
    this.email,
    required this.tenantId,
    this.role,
    this.isMfaEnabled = false,
    this.actorType,
    this.impersonatorId,
    this.impersonationExpiresAt,
  });

  bool get hasEmail => email != null && email!.isNotEmpty;
  String get displayName => email ?? id.substring(0, 8);

  /// Whether this user is currently impersonating a tenant.
  bool get isImpersonating => actorType == ActorType.impersonator;

  /// Whether the impersonation session is still valid.
  bool isImpersonationActiveAt(DateTime now) =>
      isImpersonating &&
      impersonationExpiresAt != null &&
      impersonationExpiresAt!.isAfter(now);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AuthUser &&
        other.id == id &&
        other.email == email &&
        other.tenantId == tenantId &&
        other.role == role &&
        other.isMfaEnabled == isMfaEnabled &&
        other.actorType == actorType &&
        other.impersonatorId == impersonatorId &&
        other.impersonationExpiresAt == impersonationExpiresAt;
  }

  @override
  int get hashCode => Object.hash(
    id,
    email,
    tenantId,
    role,
    isMfaEnabled,
    actorType,
    impersonatorId,
    impersonationExpiresAt,
  );

  @override
  String toString() =>
      'AuthUser(id: $id, email: $email, tenantId: $tenantId, '
      'role: $role, isMfaEnabled: $isMfaEnabled, '
      'actorType: $actorType, impersonatorId: $impersonatorId)';
}
