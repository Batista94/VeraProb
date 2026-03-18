import 'package:supabase_flutter/supabase_flutter.dart';

class OrgMember {
  final String userId;
  final String email;
  final String role;
  final DateTime invitedAt;
  final DateTime? lastSignIn;

  OrgMember({
    required this.userId,
    required this.email,
    required this.role,
    required this.invitedAt,
    this.lastSignIn,
  });
}

class PostgresUserManagementQueryService {
  final SupabaseClient _client;

  PostgresUserManagementQueryService(this._client);

  Future<List<OrgMember>> getMembers() async {
    final response = await _client.rpc('get_org_members');

    return (response as List).map((row) {
      return OrgMember(
        userId: row['user_id'] as String,
        email: row['email'] as String,
        role: row['role'] as String,
        invitedAt: DateTime.parse(row['invited_at'] as String),
        lastSignIn: row['last_sign_in'] != null
            ? DateTime.parse(row['last_sign_in'] as String)
            : null,
      );
    }).toList();
  }
}
