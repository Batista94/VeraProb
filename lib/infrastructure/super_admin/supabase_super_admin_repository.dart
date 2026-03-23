import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/super_admin/create_organization_command.dart';
import '../../domain/super_admin/i_super_admin_repository.dart';
import '../../domain/super_admin/tenant_health_snapshot.dart';

/// PostgreSQL implementation of [ISuperAdminRepository].
///
/// Write RPCs use [_authenticatedClient] (main Supabase session) so that
/// auth.uid() IS NOT NULL inside the RPC and the super_admin JWT claim is
/// validated server-side (migration 20260405000007 intent).
///
/// Read queries use [_serviceRoleClient] (service_role key) to bypass the RLS
/// hardening that blocks authenticated super admin reads on cross-tenant tables
/// (migration 20260405000006).
class SupabaseSuperAdminRepository implements ISuperAdminRepository {
  final SupabaseClient _serviceRoleClient;
  final SupabaseClient _authenticatedClient;

  SupabaseSuperAdminRepository(this._serviceRoleClient, this._authenticatedClient);

  @override
  Future<String> createOrganization(CreateOrganizationCommand cmd) async {
    final result = await _authenticatedClient.rpc(
      'super_admin_create_organization',
      params: {
        'p_legal_name': cmd.legalName,
        'p_trade_name': cmd.tradeName,
        'p_cnpj': cmd.cnpj.replaceAll(RegExp(r'\D'), ''),
        'p_timezone': cmd.timezone,
        'p_currency_code': cmd.currencyCode,
        'p_plan_type': cmd.planType,
        'p_max_vehicles': cmd.maxVehicles,
        'p_max_active_contracts': cmd.maxActiveContracts,
        'p_super_admin_user_id': cmd.superAdminUserId,
      },
    );
    return result as String;
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
  }

  @override
  Future<List<TenantHealthSnapshot>> getAllTenantHealth() async {
    final data = await _serviceRoleClient.from('super_admin_tenant_health_view').select();

    return (data as List<dynamic>)
        .map(
          (row) => TenantHealthSnapshot.fromJson(row as Map<String, dynamic>),
        )
        .toList();
  }

  @override
  Future<List<Map<String, dynamic>>> getSystemAuditLog({
    String? organizationId,
    String? severity,
    DateTime? fromDate,
    DateTime? toDate,
    int limit = 100,
  }) async {
    var query = _serviceRoleClient.from('system_audit_log').select();

    if (organizationId != null) {
      query = query.eq('organization_id', organizationId);
    }
    if (severity != null) {
      query = query.eq('severity', severity);
    }
    if (fromDate != null) {
      query = query.gte('occurred_at', fromDate.toIso8601String());
    }
    if (toDate != null) {
      query = query.lte('occurred_at', toDate.toIso8601String());
    }

    final data = await query
        .order('occurred_at', ascending: false)
        .limit(limit);

    return (data as List<dynamic>)
        .map((row) => row as Map<String, dynamic>)
        .toList();
  }
}
