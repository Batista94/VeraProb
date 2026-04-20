import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:veraprob/domain/auth/auth_failure_exception.dart';
import 'package:veraprob/domain/auth/auth_user.dart';
import 'package:veraprob/domain/enums/user_role.dart';

/// Mapper that converts a Supabase [supabase.User] into a domain [AuthUser].
///
/// Security guarantees:
/// - [tenantId] is extracted EXCLUSIVELY from `appMetadata['org_id']`,
///   which is only modifiable via Service Role (Admin API).
/// - `userMetadata` is NEVER trusted for tenant isolation ([INV-1]).
/// - Throws [AuthFailureException] if `org_id` is missing.
///
/// This mapper lives in the infrastructure layer because it knows about
/// Supabase's `supabase.User` type. The resulting [AuthUser] is pure domain ([INV-18]).
class SupabaseUserMapper {
  SupabaseUserMapper._();

  /// Maps a Supabase [supabase.User] to a domain [AuthUser].
  ///
  /// Throws [AuthFailureException] if the user lacks `org_id` in
  /// `appMetadata` (tenant isolation violation — [INV-1]).
  static AuthUser mapToAuthUser(supabase.User user) {
    final tenantId = user.appMetadata['org_id'] as String?;

    if (tenantId == null) {
      throw const AuthFailureException(
        'Usuário sem organização vinculada [INV-1].',
      );
    }

    final roleString = user.appMetadata['role'] as String?;
    final role = _mapRole(roleString);

    final isMfaEnabled = user.appMetadata['mfa_enabled'] == true;

    return AuthUser(
      id: user.id,
      email: user.email,
      tenantId: tenantId,
      role: role,
      isMfaEnabled: isMfaEnabled,
    );
  }

  /// Maps a role string from JWT claims to domain [UserRole].
  ///
  /// Returns `null` for unknown roles — the caller decides how to handle.
  static UserRole? _mapRole(String? roleString) {
    return switch (roleString) {
      'TENANT_ADMIN' => UserRole.admin,
      'OPERATOR' => UserRole.operator,
      'AUDITOR' => UserRole.auditor,
      _ => null,
    };
  }
}
