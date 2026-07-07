import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/application/admin/access_management_service.dart';
import 'package:veraprob/infrastructure/admin/postgres_access_management_service.dart';
import 'package:veraprob/infrastructure/providers/supabase_provider.dart';
import 'package:veraprob/state/providers/shared_providers.dart';

/// Tenant RBAC management wiring (Pilar 3.1). Read models are org-scoped by RLS.
final accessManagementServiceProvider = Provider<AccessManagementService>((
  ref,
) {
  return PostgresAccessManagementService(ref.watch(supabaseClientProvider));
});

/// Global permission dictionary (`tenant_permissions`) — the matrix columns.
final permissionDictionaryProvider =
    FutureProvider.autoDispose<List<TenantPermission>>((ref) {
      return ref
          .watch(accessManagementServiceProvider)
          .getPermissionDictionary();
    });

/// Tenant access profiles with resolved grants (matrix rows / master list).
final tenantRolesProvider = FutureProvider.autoDispose<List<TenantRole>>((ref) {
  return ref.watch(accessManagementServiceProvider).getRoles();
});

/// Active (non-revoked, non-expired) role assignments across the tenant, keyed
/// for per-user chips and per-role user counts. Expiry is resolved here against
/// the injected clock (INV-6) so the DTO stays transport-neutral.
final activeRoleAssignmentsProvider =
    FutureProvider.autoDispose<List<RoleAssignment>>((ref) async {
      final nowUtc = ref.watch(dateTimeProviderProvider).nowUtc();
      final all = await ref
          .watch(accessManagementServiceProvider)
          .getActiveAssignments();
      return all.where((a) => a.isActiveAt(nowUtc)).toList();
    });

/// Pending four-eyes requests awaiting a second administrator.
final pendingRoleChangesProvider =
    FutureProvider.autoDispose<List<RoleChangeRequest>>((ref) {
      return ref.watch(accessManagementServiceProvider).getPendingRequests();
    });
