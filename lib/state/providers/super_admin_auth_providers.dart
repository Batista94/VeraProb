import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/utils/jwt_utils.dart';
import 'auth_providers.dart';
import '../../domain/enums/user_role.dart';

/// Returns true if the current authenticated user is a SuperAdmin.
///
/// Reads the `super_admin` claim from the JWT access token payload (injected
/// by the custom_access_token_hook). Must decode the JWT — this claim is NOT
/// in session.user.appMetadata (which reads raw_app_meta_data from auth.users).
final isSuperAdminProvider = Provider<bool>((ref) {
  final session = ref.watch(authStateProvider).valueOrNull?.session;
  if (session == null) return false;
  final claims = decodeJwtPayload(session.accessToken);
  final meta = claims['app_metadata'] as Map<String, dynamic>?;
  return meta?['super_admin'] == true;
});

/// Returns the current SuperAdmin's user ID, or null if not a SuperAdmin.
final currentSuperAdminIdProvider = Provider<String?>((ref) {
  final isSuperAdmin = ref.watch(isSuperAdminProvider);
  if (!isSuperAdmin) return null;

  final authState = ref.watch(authStateProvider).valueOrNull;
  return authState?.session?.user.id;
});

/// Convenience alias — derives [UserRole.superAdmin] for RBAC use in handlers.
final superAdminRoleProvider = Provider<UserRole?>((ref) {
  final isSuperAdmin = ref.watch(isSuperAdminProvider);
  return isSuperAdmin ? UserRole.superAdmin : null;
});
