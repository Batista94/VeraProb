import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../application/super_admin/create_organization_handler.dart';
import '../../domain/super_admin/i_cnpj_lookup_service.dart';
import '../../domain/super_admin/i_super_admin_repository.dart';
import '../../domain/super_admin/system_audit_log_entry.dart';
import '../../domain/super_admin/tenant_health_snapshot.dart';
import '../../infrastructure/super_admin/receita_ws_cnpj_service.dart';
import '../../infrastructure/super_admin/supabase_super_admin_repository.dart';

/// Repository provider for SuperAdmin data operations.
///
/// Read operations are routed through the `super-admin-proxy` Edge Function
/// (INV-3, INV-14) — the service_role key is a Deno secret on the server,
/// never present in the Flutter WASM bundle.
final superAdminRepositoryProvider = Provider<ISuperAdminRepository>((ref) {
  return SupabaseSuperAdminRepository(Supabase.instance.client);
});

/// Provider that fetches all tenant health snapshots.
final tenantHealthSnapshotProvider = FutureProvider<List<TenantHealthSnapshot>>(
  (ref) async {
    final repo = ref.watch(superAdminRepositoryProvider);
    return repo.getAllTenantHealth();
  },
);

/// Provider that wires [CreateOrganizationHandler] with its dependencies.
final createOrganizationHandlerProvider = Provider<CreateOrganizationHandler>((
  ref,
) {
  final repo = ref.watch(superAdminRepositoryProvider);
  return CreateOrganizationHandler(repo, Supabase.instance.client);
});

/// Provider that fetches system audit log entries.
/// Accepts optional filters via a record parameter.
final systemAuditLogProvider =
    FutureProvider.family<List<SystemAuditLogEntry>, AuditLogParams>((
      ref,
      params,
    ) async {
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
  int get hashCode =>
      Object.hash(organizationId, severity, fromDate, toDate, limit);
}

/// Provider for CNPJ lookup / enrichment service.
final cnpjLookupServiceProvider = Provider<ICnpjLookupService>(
  (_) => ReceitaWsCnpjService(),
);

/// Public constructor for [AuditLogParams] (used by UI layer).
AuditLogParams auditLogParams({
  String? organizationId,
  String? severity,
  DateTime? fromDate,
  DateTime? toDate,
  int limit = 100,
}) => AuditLogParams(
  organizationId: organizationId,
  severity: severity,
  fromDate: fromDate,
  toDate: toDate,
  limit: limit,
);
