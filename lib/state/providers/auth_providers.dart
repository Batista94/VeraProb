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
final currentOrganizationIdProvider = Provider<String?>((ref) {
  final authState = ref.watch(authStateProvider).valueOrNull;
  final metadata = authState?.session?.user.appMetadata;
  return metadata?['org_id'] as String?;
});

/// Current User Role derived from the JWT custom app_metadata claim.
final currentUserRoleProvider = Provider<UserRole>((ref) {
  final authState = ref.watch(authStateProvider).valueOrNull;
  final metadata = authState?.session?.user.appMetadata;
  final roleString = metadata?['role'] as String?;

  if (roleString == 'TENANT_ADMIN') return UserRole.admin;
  if (roleString == 'AUDITOR') return UserRole.systemManager;
  return UserRole.operator;
});

/// Current operator Display Name.
final currentOperatorNameProvider = Provider<String>((ref) {
  final authState = ref.watch(authStateProvider).valueOrNull;
  return authState?.session?.user.userMetadata?['name'] ?? 'Operador';
});
