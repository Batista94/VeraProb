import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/application/admin/user_management_query_service.dart';
import 'package:veraprob/application/shared/app_types.dart';

/// PostgreSQL implementation of [UserManagementQueryService] using Supabase RPCs.
class PostgresUserManagementQueryService implements UserManagementQueryService {
  final SupabaseClient _client;

  PostgresUserManagementQueryService(this._client);

  @override
  Future<List<OrgMember>> getMembers() async {
    final response = await _client.rpc('get_org_members');

    return (response as List).map((row) {
      return OrgMember(
        userId: row['user_id'] as String,
        email: row['email'] as String,
        role: _mapDbToRole(row['role'] as String),
        invitedAt: DateTime.parse(
          row['invited_at'] as String,
        ).toUtc(), // Pilar INV-9
        lastSignIn: row['last_sign_in'] != null
            ? DateTime.parse(row['last_sign_in'] as String).toUtc()
            : null,
      );
    }).toList();
  }

  UserRole _mapDbToRole(String role) {
    switch (role) {
      case 'TENANT_ADMIN':
        return UserRole.admin;
      case 'OPERATOR':
        return UserRole.operator;
      case 'AUDITOR':
        return UserRole.auditor;
      case 'CONTRACTOR_VIEWER':
        return UserRole.contractorViewer;
      default:
        // Handle gracefully if needed, but for forensic consistency we throw
        throw ArgumentError('Unknown database role: $role');
    }
  }
}
