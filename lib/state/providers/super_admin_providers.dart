import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/application/audit/system_audit_log_service.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/application/super_admin/archive_organization_handler.dart';
import 'package:veraprob/application/super_admin/create_organization_handler.dart';
import 'package:veraprob/application/super_admin/generate_org_secret_handler.dart';
import 'package:veraprob/application/super_admin/revoke_impersonation_handler.dart';
import 'package:veraprob/application/super_admin/update_organization_quota_handler.dart';
import 'package:veraprob/application/super_admin/system_audit_log_view.dart';
import 'package:veraprob/application/super_admin/tenant_health_view.dart';
import 'package:veraprob/domain/super_admin/i_cnpj_lookup_service.dart';
import 'package:veraprob/domain/super_admin/i_super_admin_repository.dart';
import 'package:veraprob/infrastructure/audit/postgres_system_audit_log_service.dart';
import 'package:veraprob/infrastructure/super_admin/receita_ws_cnpj_service.dart';
import 'package:veraprob/infrastructure/super_admin/supabase_super_admin_repository.dart';
import 'package:veraprob/infrastructure/providers/supabase_provider.dart';
import 'auth_providers.dart';
import 'shared_providers.dart';

/// Provider for [SystemAuditLogService] — governance audit logging (Stage C).
final systemAuditLogServiceProvider = Provider<SystemAuditLogService>((ref) {
  return PostgresSystemAuditLogService(ref.watch(supabaseClientProvider));
});

/// Read operations route through the `super-admin-proxy` Edge Function
/// (INV-3, INV-14) — service_role key is a Deno secret, never in the bundle.
/// INV-30: Client injected via supabaseClientProvider (no Supabase.instance).
final superAdminRepositoryProvider = Provider<ISuperAdminRepository>((ref) {
  return SupabaseSuperAdminRepository(ref.watch(supabaseClientProvider));
});

final tenantHealthSnapshotProvider = FutureProvider<List<TenantHealthView>>((
  ref,
) async {
  final repo = ref.watch(superAdminRepositoryProvider);
  final snapshots = await repo.getAllTenantHealth();
  return snapshots.map(TenantHealthView.fromDomain).toList();
});

final updateOrganizationQuotaHandlerProvider =
    Provider<UpdateOrganizationQuotaHandler>((ref) {
      return UpdateOrganizationQuotaHandler(
        tenantValidator: TenantValidationService(
          authRepository: ref.watch(authRepositoryProvider),
        ),
        repository: ref.watch(superAdminRepositoryProvider),
        auditLogService: ref.watch(systemAuditLogServiceProvider),
      );
    });

final createOrganizationHandlerProvider = Provider<CreateOrganizationHandler>((
  ref,
) {
  final repo = ref.watch(superAdminRepositoryProvider);
  return CreateOrganizationHandler(
    repo,
    ref.watch(supabaseClientProvider),
    ref.watch(dateTimeProviderProvider),
    auditLogService: ref.watch(systemAuditLogServiceProvider),
  );
});

final systemAuditLogProvider =
    FutureProvider.family<List<SystemAuditLogView>, AuditLogParams>((
      ref,
      params,
    ) async {
      final repo = ref.watch(superAdminRepositoryProvider);
      final entries = await repo.getSystemAuditLog(
        organizationId: params.organizationId,
        severity: params.severity,
        fromDate: params.fromDate,
        toDate: params.toDate,
        limit: params.limit,
      );
      return entries.map(SystemAuditLogView.fromDomain).toList();
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

final cnpjLookupServiceProvider = Provider<ICnpjLookupService>(
  (_) => ReceitaWsCnpjService(),
);

final generateOrgSecretHandlerProvider = Provider<GenerateOrgSecretHandler>((
  ref,
) {
  return GenerateOrgSecretHandler(
    ref.watch(supabaseClientProvider),
    tenantValidator: TenantValidationService(
      authRepository: ref.watch(authRepositoryProvider),
    ),
  );
});

final archiveOrganizationHandlerProvider = Provider<ArchiveOrganizationHandler>(
  (ref) {
    return ArchiveOrganizationHandler(
      repository: ref.watch(superAdminRepositoryProvider),
      tenantValidator: TenantValidationService(
        authRepository: ref.watch(authRepositoryProvider),
      ),
    );
  },
);

final revokeImpersonationHandlerProvider = Provider<RevokeImpersonationHandler>(
  (ref) {
    return RevokeImpersonationHandler(
      ref.watch(supabaseClientProvider),
      tenantValidator: TenantValidationService(
        authRepository: ref.watch(authRepositoryProvider),
      ),
    );
  },
);

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
