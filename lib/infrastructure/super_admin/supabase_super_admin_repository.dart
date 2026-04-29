import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/super_admin/archive_organization_command.dart';
import 'package:veraprob/domain/super_admin/create_organization_command.dart';
import 'package:veraprob/domain/super_admin/i_super_admin_repository.dart';
import 'package:veraprob/domain/super_admin/system_audit_log_entry.dart';
import 'package:veraprob/domain/super_admin/tenant_health_snapshot.dart';
import 'package:veraprob/domain/super_admin/update_organization_quota_command.dart';
import 'package:veraprob/infrastructure/shared/postgres_error_interceptor.dart';

/// PostgreSQL implementation of [ISuperAdminRepository].
///
/// Read operations (`getAllTenantHealth`, `getSystemAuditLog`) are routed
/// through the `super-admin-proxy` Edge Function (INV-3, INV-14).
/// The service_role key lives exclusively in `Deno.env` on the server —
/// it is NEVER present in the Flutter WASM bundle.
///
/// Write RPCs use [_authenticatedClient] directly so that `auth.uid()` is
/// non-null inside the RPC and the super_admin JWT claim is validated
/// server-side (migration 20260405000007 intent).
class SupabaseSuperAdminRepository
    with PostgresErrorInterceptor
    implements ISuperAdminRepository {
  final SupabaseClient _authenticatedClient;

  SupabaseSuperAdminRepository(this._authenticatedClient);

  @override
  Future<String> createOrganization(CreateOrganizationCommand cmd) async {
    try {
      final result = await _authenticatedClient.rpc(
        'super_admin_create_organization',
        params: {
          'p_legal_name': cmd.legalName,
          'p_trade_name': cmd.tradeName,
          'p_cnpj': cmd.cnpj.replaceAll(RegExp(r'\D'), ''),
          'p_timezone': cmd.timezone,
          'p_currency_code': cmd.currencyCode,
          'p_plan_type': cmd.planType.name,
          'p_max_vehicles': cmd.maxVehicles,
          'p_max_active_contracts': cmd.maxActiveContracts,
          'p_super_admin_user_id': cmd.superAdminUserId,
          'p_capabilities': cmd.capabilities?.toJson(),
          'p_tool_cost_cents': cmd.toolCostCents,
          'p_dwell_time_seconds': cmd.dwellTimeSeconds,
          'p_billing_day': cmd.billingDay,
          'p_contact_email': cmd.contactEmail,
          'p_external_id': cmd.externalId,
          'p_reason': cmd.reason,
          'p_organization_type': cmd.organizationType,
        },
      );
      return result as String;
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'super_admin');
    }
  }

  @override
  Future<void> inviteFirstAdmin({
    required String orgId,
    required String email,
    required String token,
    required String invitationId,
    required DateTime expiresAtUtc,
    required String superAdminUserId,
  }) async {
    try {
      await _authenticatedClient.rpc(
        'super_admin_invite_first_admin',
        params: {
          'p_org_id': orgId,
          'p_email': email,
          'p_role': 'TENANT_ADMIN',
          'p_token': token,
          'p_invitation_id': invitationId,
          'p_expires_at': expiresAtUtc.toIso8601String(),
          'p_invited_by': superAdminUserId,
        },
      );
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'super_admin');
    }
  }

  @override
  Future<List<TenantHealthSnapshot>> getAllTenantHealth() async {
    try {
      final response = await _authenticatedClient.functions.invoke(
        'super-admin-proxy',
        body: {'action': 'list_tenant_health'},
      );
      final rows =
          (response.data as Map<String, dynamic>)['data'] as List<dynamic>;
      return rows
          .map(
            (row) => TenantHealthSnapshot.fromJson(row as Map<String, dynamic>),
          )
          .toList();
    } on Exception catch (e) {
      throw DomainException('Edge Function super-admin-proxy unavailable: $e');
    }
  }

  @override
  Future<bool> checkCnpjExists(String cnpjDigits) async {
    try {
      final result = await _authenticatedClient.rpc(
        'super_admin_check_cnpj_exists',
        params: {'p_cnpj': cnpjDigits},
      );
      return result as bool;
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'super_admin');
    }
  }

  @override
  Future<List<SystemAuditLogEntry>> getSystemAuditLog({
    String? organizationId,
    String? severity,
    DateTime? fromDate,
    DateTime? toDate,
    int limit = 100,
  }) async {
    final params = <String, dynamic>{'limit': limit};
    if (organizationId != null) params['organization_id'] = organizationId;
    if (severity != null) params['severity'] = severity;
    if (fromDate != null) params['from_date'] = fromDate.toIso8601String();
    if (toDate != null) params['to_date'] = toDate.toIso8601String();

    try {
      final response = await _authenticatedClient.functions.invoke(
        'super-admin-proxy',
        body: {'action': 'get_audit_log', 'params': params},
      );
      final rows =
          (response.data as Map<String, dynamic>)['data'] as List<dynamic>;
      return rows
          .map(
            (row) => SystemAuditLogEntry.fromJson(row as Map<String, dynamic>),
          )
          .toList();
    } on Exception catch (e) {
      throw DomainException('Edge Function super-admin-proxy unavailable: $e');
    }
  }

  @override
  Future<void> updateOrganizationQuota(
    UpdateOrganizationQuotaCommand cmd,
  ) async {
    try {
      await _authenticatedClient.rpc(
        'super_admin_update_organization_quota',
        params: {
          'p_org_id': cmd.organizationId,
          'p_new_plan_type': cmd.newPlanType,
          'p_new_max_vehicles': cmd.newMaxVehicles,
          'p_new_max_contracts': cmd.newMaxActiveContracts,
          'p_super_admin_user_id': cmd.superAdminUserId,
          'p_reason': cmd.reason,
          'p_capabilities': cmd.capabilities?.toJson(),
          'p_tool_cost_cents': cmd.toolCostCents,
          'p_dwell_time_seconds': cmd.dwellTimeSeconds,
          'p_billing_day': cmd.billingDay,
          'p_contact_email': cmd.contactEmail,
          'p_external_id': cmd.externalId,
          'p_organization_type': cmd.organizationType,
        },
      );
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'super_admin');
    }
  }

  @override
  Future<void> archiveOrganization(ArchiveOrganizationCommand cmd) async {
    try {
      await _authenticatedClient.rpc(
        'super_admin_archive_organization',
        params: {
          'p_org_id': cmd.orgId,
          'p_reason': cmd.reason,
          'p_super_admin_id': cmd.superAdminUserId,
        },
      );
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'super_admin');
    }
  }

  @override
  Future<void> unarchiveOrganization({
    required String orgId,
    required String reason,
    required String superAdminId,
  }) async {
    try {
      await _authenticatedClient.rpc(
        'super_admin_unarchive_organization',
        params: {
          'p_org_id': orgId,
          'p_reason': reason,
          'p_super_admin_id': superAdminId,
        },
      );
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'super_admin');
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getTenantMembers(String orgId) async {
    try {
      final response = await _authenticatedClient.rpc(
        'super_admin_get_org_members',
        params: {'p_org_id': orgId},
      );
      return (response as List).cast<Map<String, dynamic>>();
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'super_admin');
    }
  }

  @override
  Future<void> toggleTenantMemberStatus({
    required String orgId,
    required String userId,
    required bool isActive,
  }) async {
    try {
      await _authenticatedClient.rpc(
        'super_admin_toggle_member_status',
        params: {
          'p_org_id': orgId,
          'p_user_id': userId,
          'p_is_active': isActive,
        },
      );
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'super_admin');
    }
  }

  @override
  Future<void> resendInvitation({
    required String email,
    required String orgName,
  }) async {
    try {
      await _authenticatedClient.functions.invoke(
        'notify-invite',
        body: {
          'email': email,
          'inviteUrl': 'Entre em contato com o suporte para um novo link',
          'orgName': orgName,
        },
      );
    } catch (e) {
      // Se não for possível usar as exceptions do postgrest, mapeamos genérico ou deixamos subir
      rethrow;
    }
  }

  @override
  Future<void> addAdminToOrganization({
    required String orgId,
    required String email,
    required String invitationId,
    required String token,
    required DateTime expiresAtUtc,
    required String superAdminUserId,
  }) async {
    try {
      await _authenticatedClient.rpc(
        'super_admin_add_org_admin',
        params: {
          'p_org_id': orgId,
          'p_email': email,
          'p_invitation_id': invitationId,
          'p_token': token,
          'p_expires_at': expiresAtUtc.toIso8601String(),
          'p_invited_by': superAdminUserId,
        },
      );
    } on PostgrestException catch (e) {
      if (e.code == 'P0005') {
        throw DomainException(
          'Já existe um convite pendente para $email nesta organização.',
        );
      }
      if (e.code == 'P0006') {
        throw DomainException(
          '$email já possui um perfil ativo nesta organização.',
        );
      }
      throw mapPostgrestToDomainException(e, resourceType: 'super_admin');
    }
  }
}
