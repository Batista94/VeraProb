import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/application/admin/access_management_service.dart';

/// Supabase implementation of [AccessManagementService].
///
/// Reads are org-scoped by RLS (top-level `organization_id` claim); writes go
/// through the SECURITY DEFINER RPCs which own the subset guard, org scope and
/// four-eyes routing. No authorization logic lives here.
class PostgresAccessManagementService implements AccessManagementService {
  final SupabaseClient _client;

  PostgresAccessManagementService(this._client);

  @override
  Future<List<TenantPermission>> getPermissionDictionary() async {
    final rows = await _client
        .from('tenant_permissions')
        .select(
          'key, module, action, label_pt, description, is_sensitive, is_scopable',
        )
        .order('module')
        .order('action');

    return rows.map(parsePermission).toList();
  }

  @override
  Future<List<TenantRole>> getRoles() async {
    final rows = await _client
        .from('tenant_roles')
        .select(
          'id, name, description, is_system, '
          'tenant_role_permissions(permission_key, scope)',
        )
        .order('name');

    return rows.map(parseRole).toList();
  }

  @override
  Future<List<RoleAssignment>> getActiveAssignments() async {
    final rows = await _client
        .from('user_tenant_roles')
        .select('user_id, tenant_role_id, valid_until')
        .isFilter('revoked_at', null);

    return rows.map(parseAssignment).toList();
  }

  @override
  Future<List<RoleChangeRequest>> getPendingRequests() async {
    final rows = await _client
        .from('role_change_requests')
        .select('id, request_type, requested_by, payload, created_at')
        .eq('status', 'PENDING')
        .order('created_at', ascending: false);

    return rows.map(parseRequest).toList();
  }

  // ── Pure row → DTO mappers (unit-tested without a live client) ───────────────

  @visibleForTesting
  static TenantPermission parsePermission(Map<String, dynamic> row) =>
      TenantPermission(
        key: row['key'] as String,
        module: row['module'] as String,
        action: row['action'] as String,
        labelPt: row['label_pt'] as String,
        description: (row['description'] as String?) ?? '',
        isSensitive: row['is_sensitive'] as bool,
        isScopable: row['is_scopable'] as bool,
      );

  @visibleForTesting
  static TenantRole parseRole(Map<String, dynamic> row) {
    final rawGrants = (row['tenant_role_permissions'] as List?) ?? const [];
    final grants = rawGrants.map((g) {
      final grant = g as Map<String, dynamic>;
      final scope = grant['scope'] as Map<String, dynamic>?;
      final ids = (scope?['contract_ids'] as List?)
          ?.whereType<String>()
          .toSet();
      return RolePermissionGrant(
        permissionKey: grant['permission_key'] as String,
        contractScopeIds: ids ?? const <String>{},
      );
    }).toList();

    return TenantRole(
      id: row['id'] as String,
      name: row['name'] as String,
      description: row['description'] as String?,
      isSystem: row['is_system'] as bool,
      grants: grants,
    );
  }

  @visibleForTesting
  static RoleAssignment parseAssignment(Map<String, dynamic> row) {
    final rawUntil = row['valid_until'] as String?;
    return RoleAssignment(
      userId: row['user_id'] as String,
      roleId: row['tenant_role_id'] as String,
      validUntilUtc: rawUntil == null ? null : DateTime.parse(rawUntil).toUtc(),
    );
  }

  @visibleForTesting
  static RoleChangeRequest parseRequest(Map<String, dynamic> row) =>
      RoleChangeRequest(
        id: row['id'] as String,
        requestType: row['request_type'] as String,
        requestedBy: row['requested_by'] as String,
        payload: (row['payload'] as Map<String, dynamic>?) ?? const {},
        createdAtUtc: DateTime.parse(row['created_at'] as String).toUtc(),
      );

  @override
  Future<void> createRole({
    required String name,
    String? description,
    required List<RolePermissionGrant> grants,
  }) async {
    await _client.rpc<void>(
      'create_tenant_role',
      params: <String, Object?>{
        'p_name': name,
        'p_description': description,
        'p_perm_grants': grants.map((g) => g.toJson()).toList(),
      },
    );
  }

  @override
  Future<void> updateRolePermissions({
    required String roleId,
    required List<RolePermissionGrant> grants,
  }) async {
    await _client.rpc<void>(
      'update_tenant_role_permissions',
      params: <String, Object?>{
        'p_role_id': roleId,
        'p_perm_grants': grants.map((g) => g.toJson()).toList(),
      },
    );
  }

  @override
  Future<void> assignRole({
    required String userId,
    required String roleId,
    DateTime? validUntilUtc,
  }) async {
    await _client.rpc<void>(
      'assign_tenant_role',
      params: <String, Object?>{
        'p_target_user': userId,
        'p_role_id': roleId,
        'p_valid_until': validUntilUtc?.toUtc().toIso8601String(),
      },
    );
  }

  @override
  Future<void> revokeRole({
    required String userId,
    required String roleId,
  }) async {
    await _client.rpc<void>(
      'revoke_tenant_role',
      params: <String, Object?>{'p_target_user': userId, 'p_role_id': roleId},
    );
  }

  @override
  Future<void> approveRequest(String requestId) async {
    await _client.rpc<void>(
      'approve_role_change',
      params: <String, Object?>{'p_request_id': requestId},
    );
  }

  @override
  Future<void> rejectRequest(String requestId) async {
    await _client.rpc<void>(
      'reject_role_change',
      params: <String, Object?>{'p_request_id': requestId},
    );
  }
}
