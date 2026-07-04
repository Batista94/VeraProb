import 'package:flutter/foundation.dart';

/// Application port + DTOs for tenant-customizable RBAC management (Pilar 3.1).
///
/// Reads the org-scoped role catalog / assignments / four-eyes queue and drives
/// the SECURITY DEFINER mutation RPCs (`create_tenant_role`,
/// `update_tenant_role_permissions`, `assign_tenant_role`, `revoke_tenant_role`,
/// `approve_role_change`, `reject_role_change`). RLS + those RPCs are the source
/// of truth; this layer never enforces authorization on its own (INV-13 keeps
/// `features/` off `infrastructure/`).

/// A row of the global permission dictionary (`tenant_permissions`).
@immutable
class TenantPermission {
  final String key;
  final String module;
  final String action;
  final String labelPt;
  final String description;
  final bool isSensitive;
  final bool isScopable;

  const TenantPermission({
    required this.key,
    required this.module,
    required this.action,
    required this.labelPt,
    required this.description,
    required this.isSensitive,
    required this.isScopable,
  });
}

/// A single permission granted to a role, with an optional resource allowlist
/// (ABAC-lite). Empty [contractScopeIds] = unrestricted within the tenant.
@immutable
class RolePermissionGrant {
  final String permissionKey;
  final Set<String> contractScopeIds;

  const RolePermissionGrant({
    required this.permissionKey,
    this.contractScopeIds = const <String>{},
  });

  /// Serializes to the `perm_grants` element shape expected by the RPCs:
  /// `{"key": "...", "scope": {"contract_ids": [...]}}`. The `scope` key is
  /// omitted when unrestricted (mirrors `_rbac_validate_grants`).
  Map<String, Object?> toJson() => <String, Object?>{
    'key': permissionKey,
    if (contractScopeIds.isNotEmpty)
      'scope': <String, Object?>{'contract_ids': contractScopeIds.toList()},
  };
}

/// A tenant-defined access profile with its resolved permission grants.
@immutable
class TenantRole {
  final String id;
  final String name;
  final String? description;
  final bool isSystem;
  final List<RolePermissionGrant> grants;

  const TenantRole({
    required this.id,
    required this.name,
    required this.description,
    required this.isSystem,
    required this.grants,
  });

  Set<String> get permissionKeys => grants.map((g) => g.permissionKey).toSet();
}

/// An active `user_tenant_roles` assignment (revoked rows excluded upstream).
@immutable
class RoleAssignment {
  final String userId;
  final String roleId;
  final DateTime? validUntilUtc;

  const RoleAssignment({
    required this.userId,
    required this.roleId,
    required this.validUntilUtc,
  });

  bool isActiveAt(DateTime nowUtc) =>
      validUntilUtc == null || validUntilUtc!.isAfter(nowUtc);
}

/// A pending four-eyes `role_change_requests` row awaiting a second admin.
@immutable
class RoleChangeRequest {
  final String id;
  final String
  requestType; // CREATE_ROLE | UPDATE_ROLE_PERMISSIONS | GRANT_ROLE
  final String requestedBy;
  final Map<String, Object?> payload;
  final DateTime createdAtUtc;

  const RoleChangeRequest({
    required this.id,
    required this.requestType,
    required this.requestedBy,
    required this.payload,
    required this.createdAtUtc,
  });

  /// Permission keys carried in the request payload (empty for GRANT_ROLE).
  List<String> get proposedPermissionKeys {
    final grants = payload['perm_grants'];
    if (grants is! List) return const <String>[];
    return grants
        .whereType<Map<Object?, Object?>>()
        .map((e) => e['key'])
        .whereType<String>()
        .toList();
  }
}

/// Decoupled from infrastructure (Supabase). Implemented by
/// `PostgresAccessManagementService`.
abstract class AccessManagementService {
  Future<List<TenantPermission>> getPermissionDictionary();
  Future<List<TenantRole>> getRoles();

  /// Non-revoked assignments across the tenant. Time-bound expiry is filtered
  /// by the caller against `IDateTimeProvider.nowUtc()` (INV-6).
  Future<List<RoleAssignment>> getActiveAssignments();
  Future<List<RoleChangeRequest>> getPendingRequests();

  Future<void> createRole({
    required String name,
    String? description,
    required List<RolePermissionGrant> grants,
  });

  Future<void> updateRolePermissions({
    required String roleId,
    required List<RolePermissionGrant> grants,
  });

  Future<void> assignRole({
    required String userId,
    required String roleId,
    DateTime? validUntilUtc,
  });

  Future<void> revokeRole({required String userId, required String roleId});

  Future<void> approveRequest(String requestId);
  Future<void> rejectRequest(String requestId);
}
