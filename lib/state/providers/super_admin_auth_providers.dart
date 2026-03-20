import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_providers.dart';
import '../../domain/enums/user_role.dart';

/// Returns true if the current authenticated user is a SuperAdmin.
///
/// Reads the `super_admin` claim from JWT app_metadata (injected by hook).
/// Kept separate from [auth_providers.dart] to avoid coupling SuperAdmin
/// state into tenant provider trees.
final isSuperAdminProvider = Provider<bool>((ref) {
  final authState = ref.watch(authStateProvider).valueOrNull;
  final metadata = authState?.session?.user.appMetadata;
  return metadata?['super_admin'] == true;
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
