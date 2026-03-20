import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/environment.dart';
import '../../domain/super_admin/i_super_admin_repository.dart';
import '../../domain/super_admin/tenant_health_snapshot.dart';
import '../../infrastructure/super_admin/supabase_super_admin_repository.dart';

/// Isolated service_role Supabase client for SuperAdmin operations.
///
/// D3: instantiated with service_role key — never Supabase.initialize() again.
/// Never passed to tenant providers.
///
/// URL resolved from [EnvironmentConfig.supabaseUrl] (--dart-define).
/// Service_role key from [EnvironmentConfig.supabaseServiceRoleKey].
final superAdminSupabaseClientProvider = Provider<SupabaseClient>((ref) {
  return SupabaseClient(
    EnvironmentConfig.supabaseUrl,
    EnvironmentConfig.supabaseServiceRoleKey,
  );
});

/// Repository provider for SuperAdmin data operations.
final superAdminRepositoryProvider = Provider<ISuperAdminRepository>((ref) {
  final client = ref.watch(superAdminSupabaseClientProvider);
  return SupabaseSuperAdminRepository(client);
});

/// Provider that fetches all tenant health snapshots.
final tenantHealthSnapshotProvider =
    FutureProvider<List<TenantHealthSnapshot>>((ref) async {
  final repo = ref.watch(superAdminRepositoryProvider);
  return repo.getAllTenantHealth();
});

/// Provider that fetches system audit log entries.
/// Accepts optional filters via a record parameter.
final systemAuditLogProvider =
    FutureProvider.family<List<Map<String, dynamic>>, AuditLogParams>(
        (ref, params) async {
  final repo = ref.watch(superAdminRepositoryProvider);
  return repo.getSystemAuditLog(
    organizationId: params.organizationId,
    severity: params.severity,
    fromDate: params.fromDate,
    toDate: params.toDate,
    limit: params.limit,
  );
});

/// Parameter record for [systemAuditLogProvider].
class AuditLogParams {
  final String? organizationId;
  final String? severity;
  final DateTime? fromDate;
  final DateTime? toDate;
  final int limit;

  const AuditLogParams({
    this.organizationId,
    this.severity,
    this.fromDate,
    this.toDate,
    this.limit = 100,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuditLogParams &&
          organizationId == other.organizationId &&
          severity == other.severity &&
          fromDate == other.fromDate &&
          toDate == other.toDate &&
          limit == other.limit;

  @override
  int get hashCode => Object.hash(
        organizationId,
        severity,
        fromDate,
        toDate,
        limit,
      );
}

/// Public constructor for [AuditLogParams] (used by UI layer).
AuditLogParams auditLogParams({
  String? organizationId,
  String? severity,
  DateTime? fromDate,
  DateTime? toDate,
  int limit = 100,
}) =>
    AuditLogParams(
      organizationId: organizationId,
      severity: severity,
      fromDate: fromDate,
      toDate: toDate,
      limit: limit,
    );
