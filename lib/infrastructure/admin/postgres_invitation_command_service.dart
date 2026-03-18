import 'package:supabase_flutter/supabase_flutter.dart';
import '../../application/admin/invitation_command_service.dart';
import '../../domain/enums/user_role.dart';

/// PostgreSQL implementation of [InvitationCommandService] using Supabase RPCs.
class PostgresInvitationCommandService implements InvitationCommandService {
  final SupabaseClient _client;

  PostgresInvitationCommandService(this._client);

  @override
  Future<void> inviteUser({
    required String email,
    required UserRole role,
    required String token,
    required String invitationId,
    required DateTime expiresAtUtc,
  }) async {
    await _client.rpc(
      'invite_user',
      params: {
        'p_email': email,
        'p_role': _mapRoleToDb(role),
        'p_token': token,
        'p_invitation_id': invitationId,
        'p_expires_at': expiresAtUtc.toIso8601String(),
      },
    );
  }

  @override
  Future<void> acceptInvitation({
    required String token,
    required String userId,
  }) async {
    await _client.rpc(
      'accept_invitation',
      params: {'p_token': token, 'p_user_id': userId},
    );
  }

  @override
  Future<void> revokeInvitation({required String invitationId}) async {
    await _client.rpc(
      'revoke_invitation',
      params: {'p_invitation_id': invitationId},
    );
  }

  String _mapRoleToDb(UserRole role) {
    switch (role) {
      case UserRole.admin:
        return 'TENANT_ADMIN';
      case UserRole.operator:
        return 'OPERATOR';
      case UserRole.auditor:
        return 'AUDITOR';
      case UserRole.contractorViewer:
        return 'CONTRACTOR_VIEWER';
    }
  }
}
