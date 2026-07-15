import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/core/utils/jwt_utils.dart';
import 'package:veraprob/domain/auth/i_auth_repository.dart';
import 'package:veraprob/domain/enums/user_role.dart';
export 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/services/permission_service.dart';
import 'package:veraprob/infrastructure/auth/supabase_auth_repository.dart';
import 'package:veraprob/infrastructure/providers/supabase_provider.dart';

/// Stream of auth state changes.
/// INV-30: Client injected via supabaseClientProvider.
final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(supabaseClientProvider).auth.onAuthStateChange;
});

/// Current operator ID (from auth session in production).
final currentOperatorIdProvider = Provider<String?>((ref) {
  final authState = ref.watch(authStateProvider).value;
  return authState?.session?.user.id;
});

/// Extracts the strict `organization_id` boundary from the JWT claims
/// injected by the Postgres `custom_access_token_hook`.
/// Direct fetcher for organization ID when JWT metadata is missing/syncing.
/// INV-30: Client injected via supabaseClientProvider.
final organizationIdFetcherProvider = FutureProvider<String?>((ref) async {
  final authState = ref.watch(authStateProvider).value;
  final userId = authState?.session?.user.id;
  if (userId == null) return null;

  try {
    final response = await ref
        .watch(supabaseClientProvider)
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
  final session = ref.watch(authStateProvider).value?.session;

  // 1. Try JWT payload claims (primary — hook-injected)
  final fromJwt = _jwtAppMeta(session)?['org_id'] as String?;
  if (fromJwt != null) return fromJwt;

  // 2. Fallback to the async fetcher result if available
  return ref.watch(organizationIdFetcherProvider).value;
});

/// Current User Role derived from the JWT custom app_metadata claim.
final currentUserRoleProvider = Provider<UserRole>((ref) {
  final session = ref.watch(authStateProvider).value?.session;
  final meta = _jwtAppMeta(session);

  // SuperAdmin check — must run before role string mapping (D2).
  if (meta?['super_admin'] == true) return UserRole.superAdmin;

  final roleString = meta?['role'] as String?;
  if (roleString == 'TENANT_ADMIN') return UserRole.admin;
  if (roleString == 'AUDITOR') return UserRole.auditor;
  return UserRole.operator;
});

/// Fine-grained permission keys (`module:action`) from the JWT claim
/// `app_metadata.permissions`, injected by `custom_access_token_hook`.
///
/// Additive layer over [currentUserRoleProvider] (coarse trust root): this
/// governs fine gating. Derives from [authStateProvider], so it recomputes on
/// every `AuthChangeEvent` — a user switch zeroes the set automatically (no
/// stale RAM cache). Boundary parse to `Set<String>` (INV-7 — no `dynamic`).
final currentPermissionsProvider = Provider<Set<String>>((ref) {
  final session = ref.watch(authStateProvider).value?.session;
  final raw = _jwtAppMeta(session)?['permissions'];
  if (raw is! List) return const <String>{};
  return raw.whereType<String>().toSet();
});

/// ABAC-lite resource scopes from `app_metadata.perm_scopes`.
///
/// Maps a permission key to the allowlist of resource IDs it is restricted to.
/// A permission present in [currentPermissionsProvider] but ABSENT here is
/// unrestricted within the tenant (mirrors `public.has_permission_on`).
final permScopesProvider = Provider<Map<String, Set<String>>>((ref) {
  final session = ref.watch(authStateProvider).value?.session;
  final raw = _jwtAppMeta(session)?['perm_scopes'];
  if (raw is! Map) return const <String, Set<String>>{};
  final result = <String, Set<String>>{};
  raw.forEach((key, value) {
    if (key is String && value is List) {
      result[key] = value.whereType<String>().toSet();
    }
  });
  return result;
});

/// Permissions version tag (`app_metadata.perms_v`) carried by the current
/// access token — an epoch of `max(tenant_roles.updated_at)` over the user's
/// active roles. Compared against `current_perms_v()` to detect stale claims.
final tokenPermsVersionProvider = Provider<int>((ref) {
  final session = ref.watch(authStateProvider).value?.session;
  final raw = _jwtAppMeta(session)?['perms_v'];
  return raw is num ? raw.toInt() : 0;
});

/// Fine-grained permission resolver ([PermissionService]) built from the
/// current claims. Widgets call `hasPermission()` / `hasPermissionOn()` for
/// UX gating; parity with the DB helpers is enforced by shared test cases.
final permissionServiceProvider = Provider<PermissionService>((ref) {
  return PermissionService(
    permissions: ref.watch(currentPermissionsProvider),
    scopes: ref.watch(permScopesProvider),
  );
});

/// Current operator Display Name.
final currentOperatorNameProvider = Provider<String>((ref) {
  final authState = ref.watch(authStateProvider).value;
  return (authState?.session?.user.userMetadata?['name'] as String?) ??
      'Operador';
});

/// Current operator Email — used for Pillar C (Audit Trail) forensic logging.
///
/// Every sealed/refused verdict logs this email alongside the user ID
/// in the immutable ledger for forensic traceability.
final currentOperatorEmailProvider = Provider<String>((ref) {
  final authState = ref.watch(authStateProvider).value;
  return authState?.session?.user.email ?? '';
});

/// Riverpod provider for [IAuthRepository].
///
/// Widgets MUST use this provider for all auth operations (signIn, signOut,
/// signUp, refreshSession). Eliminates direct `Supabase.instance.client.auth`
/// calls from the presentation layer (SRP-UI-LEAK prevention).
/// INV-30: Client injected via supabaseClientProvider.
final authRepositoryProvider = Provider<IAuthRepository>((ref) {
  return SupabaseAuthRepository(ref.watch(supabaseClientProvider));
});

/// Current session identifier — used for INV-1 tenant validation.
///
/// Returns the current access token as the session identifier.
/// The [TenantValidationService] uses this to validate that the
/// command's [organizationId] matches the JWT claim.
///
/// Returns `null` if there is no active session.
final currentSessionIdProvider = Provider<String?>((ref) {
  final session = ref.watch(authStateProvider).value?.session;
  return session?.accessToken;
});
