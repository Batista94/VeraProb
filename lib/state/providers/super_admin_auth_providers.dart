import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/core/config/supabase_client.dart';
import 'package:veraprob/core/utils/jwt_utils.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/super_admin/i_mfa_repository.dart';
import 'package:veraprob/infrastructure/super_admin/supabase_mfa_repository.dart';
import 'auth_providers.dart';

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

/// Returns true if the current SuperAdmin has completed MFA (AAL2).
///
/// Relaxed in development: returns true if ENV=dev even if AAL1 (INV-6 relaxation).
final isSuperAdminAal2Provider = Provider<bool>((ref) {
  final isSuperAdmin = ref.watch(isSuperAdminProvider);
  if (!isSuperAdmin) return false;

  // Relax MFA requirement in development environment.
  const isDev = String.fromEnvironment('ENV') == 'dev';

  final session = ref.watch(authStateProvider).valueOrNull?.session;
  if (session == null) return false;
  final claims = decodeJwtPayload(session.accessToken);

  return isDev || claims['aal'] == 'aal2';
});

/// Convenience alias — derives [UserRole.superAdmin] for RBAC use in handlers.
final superAdminRoleProvider = Provider<UserRole?>((ref) {
  final isSuperAdmin = ref.watch(isSuperAdminProvider);
  return isSuperAdmin ? UserRole.superAdmin : null;
});

/// Riverpod provider for [IMfaRepository].
///
/// [IMfaRepository] and [SupabaseMfaRepository] already exist —
/// this wires the missing Riverpod binding.
/// Widgets that handle TOTP enrollment and challenge verification
/// MUST consume this provider instead of instantiating the repository directly.
final mfaRepositoryProvider = Provider<IMfaRepository>((ref) {
  return SupabaseMfaRepository(supabase);
});
