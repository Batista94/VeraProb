import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/config/supabase_client.dart';
import '../../domain/enums/user_role.dart';

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

/// Extracts the strict `organization_id` boundary from the JWT claims.
/// Injected by the Postgres `custom_access_token_hook`.
final currentOrganizationIdProvider = Provider<String?>((ref) {
  final authState = ref.watch(authStateProvider).valueOrNull;
  
  // 1. Try JWT metadata (fastest)
  final metadata = authState?.session?.user.appMetadata;
  final fromMetadata = metadata?['org_id'] as String?;
  if (fromMetadata != null) return fromMetadata;

  // 2. Fallback to the async fetcher result if available
  return ref.watch(organizationIdFetcherProvider).valueOrNull;
});

/// Current User Role derived from the JWT custom app_metadata claim.
final currentUserRoleProvider = Provider<UserRole>((ref) {
  final authState = ref.watch(authStateProvider).valueOrNull;
  final metadata = authState?.session?.user.appMetadata;
  final roleString = metadata?['role'] as String?;

  if (roleString == 'TENANT_ADMIN') return UserRole.admin;
  if (roleString == 'AUDITOR') return UserRole.auditor;
  return UserRole.operator;
});

/// Current operator Display Name.
final currentOperatorNameProvider = Provider<String>((ref) {
  final authState = ref.watch(authStateProvider).valueOrNull;
  return authState?.session?.user.userMetadata?['name'] ?? 'Operador';
});
