import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/core/config/supabase_client.dart';
import 'package:veraprob/core/utils/jwt_utils.dart';
import 'package:veraprob/domain/auth/i_auth_repository.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/infrastructure/auth/supabase_auth_repository.dart';

/// Stream of auth state changes.
final authStateProvider = StreamProvider<AuthState>((ref) {
  return supabase.auth.onAuthStateChange;
});

/// Current operator ID (from auth session in production).
final currentOperatorIdProvider = Provider<String?>((ref) {
  final authState = ref.watch(authStateProvider).valueOrNull;
  return authState?.session?.user.id;
});

/// Extracts the strict `organization_id` boundary from the JWT claims
/// injected by the Postgres `custom_access_token_hook`.
/// Direct fetcher for organization ID when JWT metadata is missing/syncing.
final organizationIdFetcherProvider = FutureProvider<String?>((ref) async {
  final authState = ref.watch(authStateProvider).valueOrNull;
  final userId = authState?.session?.user.id;
  if (userId == null) return null;

  try {
    final response = await supabase
        .from('user_roles')
        .select('organization_id')
        .eq('user_id', userId)
        .maybeSingle();

    return response?['organization_id'] as String?;
  } catch (e) {
    debugPrint('[Auth] organizationIdFetcherProvider failed: $e');
    return null;
  }
});

/// Helper: decodes the JWT access token and returns `app_metadata` claims.
///
/// GoTrue's custom_access_token_hook injects org_id / role / super_admin into
/// the ACCESS TOKEN payload. These are NOT in session.user.appMetadata, which
/// reads raw_app_meta_data — a separate static field in auth.users.
Map<String, dynamic>? _jwtAppMeta(Session? session) {
  if (session == null) return null;
  final claims = decodeJwtPayload(session.accessToken);
  return claims['app_metadata'] as Map<String, dynamic>?;
}

/// Extracts the strict `organization_id` boundary from the JWT claims.
/// Injected by the Postgres `custom_access_token_hook`.
final currentOrganizationIdProvider = Provider<String?>((ref) {
  final session = ref.watch(authStateProvider).valueOrNull?.session;

  // 1. Try JWT payload claims (primary — hook-injected)
  final fromJwt = _jwtAppMeta(session)?['org_id'] as String?;
  if (fromJwt != null) return fromJwt;

  // 2. Fallback to the async fetcher result if available
  return ref.watch(organizationIdFetcherProvider).valueOrNull;
});

/// Current User Role derived from the JWT custom app_metadata claim.
final currentUserRoleProvider = Provider<UserRole>((ref) {
  final session = ref.watch(authStateProvider).valueOrNull?.session;
  final meta = _jwtAppMeta(session);

  // SuperAdmin check — must run before role string mapping (D2).
  if (meta?['super_admin'] == true) return UserRole.superAdmin;

  final roleString = meta?['role'] as String?;
  if (roleString == 'TENANT_ADMIN') return UserRole.admin;
  if (roleString == 'AUDITOR') return UserRole.auditor;
  return UserRole.operator;
});

/// Current operator Display Name.
final currentOperatorNameProvider = Provider<String>((ref) {
  final authState = ref.watch(authStateProvider).valueOrNull;
  return authState?.session?.user.userMetadata?['name'] ?? 'Operador';
});

/// Current operator Email — used for Pillar C (Audit Trail) forensic logging.
///
/// Every sealed/refused verdict logs this email alongside the user ID
/// in the immutable ledger for forensic traceability.
final currentOperatorEmailProvider = Provider<String>((ref) {
  final authState = ref.watch(authStateProvider).valueOrNull;
  return authState?.session?.user.email ?? '';
});

/// Riverpod provider for [IAuthRepository].
///
/// Widgets MUST use this provider for all auth operations (signIn, signOut,
/// signUp, refreshSession). Eliminates direct `Supabase.instance.client.auth`
/// calls from the presentation layer (SRP-UI-LEAK prevention).
final authRepositoryProvider = Provider<IAuthRepository>((ref) {
  return SupabaseAuthRepository();
});

/// Current session identifier — used for INV-1 tenant validation.
///
/// Returns the current access token as the session identifier.
/// The [TenantValidationService] uses this to validate that the
/// command's [organizationId] matches the JWT claim.
///
/// Returns `null` if there is no active session.
final currentSessionIdProvider = Provider<String?>((ref) {
  final session = ref.watch(authStateProvider).valueOrNull?.session;
  return session?.accessToken;
});
