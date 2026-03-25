import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../application/super_admin/create_organization_handler.dart';
import '../../core/config/environment.dart';
import '../../domain/super_admin/i_cnpj_lookup_service.dart';
import '../../domain/super_admin/i_super_admin_repository.dart';
import '../../domain/super_admin/system_audit_log_entry.dart';
import '../../domain/super_admin/tenant_health_snapshot.dart';
import '../../infrastructure/super_admin/receita_ws_cnpj_service.dart';
import '../../infrastructure/super_admin/supabase_super_admin_repository.dart';

/// Isolated service_role Supabase client for SuperAdmin operations.
///
/// D3: instantiated with service_role key — never Supabase.initialize() again.
/// Never passed to tenant providers.
///
/// Credential resolution order (mirrors SupabaseConfig.initialize):
///  1. `--dart-define` values (CI/CD — production)
///  2. `.env` file via dotenv (local dev — requires SUPABASE_SERVICE_ROLE_KEY)
final superAdminSupabaseClientProvider = Provider<SupabaseClient>((ref) {
  final url = EnvironmentConfig.supabaseUrl.isNotEmpty
      ? EnvironmentConfig.supabaseUrl
      : (dotenv.env['SUPABASE_URL'] ?? '');

  final serviceKey = EnvironmentConfig.supabaseServiceRoleKey.isNotEmpty
      ? EnvironmentConfig.supabaseServiceRoleKey
      : (dotenv.env['SUPABASE_SERVICE_ROLE_KEY'] ?? '');

  // EmptyLocalStorage prevents this client from recovering the user session
  // from browser localStorage (which is shared with the main anon client via
  // the same sb-<host>-auth-token key). Without this, auth.uid() returns
  // the super admin's UUID inside RPCs instead of NULL, bypassing the
  // service_role path in super_admin_create_organization / invite_first_admin.
  return SupabaseClient(
    url,
    serviceKey,
    authOptions: const FlutterAuthClientOptions(
      localStorage: EmptyLocalStorage(),
      autoRefreshToken: false,
    ),
  );
});

/// Repository provider for SuperAdmin data operations.
///
/// Passes two clients:
///  - service_role client (for cross-tenant reads that RLS would otherwise block)
///  - authenticated client (for write RPCs that validate the super_admin JWT claim)
final superAdminRepositoryProvider = Provider<ISuperAdminRepository>((ref) {
  final serviceRoleClient = ref.watch(superAdminSupabaseClientProvider);
  return SupabaseSuperAdminRepository(
    serviceRoleClient,
    Supabase.instance.client,
  );
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
