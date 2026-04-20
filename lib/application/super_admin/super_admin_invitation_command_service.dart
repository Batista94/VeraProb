import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/application/admin/invitation_command_service.dart';
import 'package:veraprob/domain/enums/user_role.dart';

/// SuperAdmin implementation of [InvitationCommandService].
///
/// Delegates to the `super_admin_invite_first_admin` RPC, which:
/// - Accepts [p_org_id] explicitly (SuperAdmin has no org_id JWT claim — D4).
/// - Validates the `super_admin: true` JWT claim server-side.
///
/// Receives the authenticated client (main Supabase session) so that
/// auth.uid() IS NOT NULL inside the RPC and the super_admin claim is verified.
///
/// [orgId] is captured at construction time by [CreateOrganizationHandler]
/// after the org is created (contextual service — not a singleton).
class SuperAdminInvitationCommandService implements InvitationCommandService {
  final SupabaseClient _client;
  final String _orgId;
  final String _superAdminUserId;

  SuperAdminInvitationCommandService(
    this._client, {
    required String orgId,
    required String superAdminUserId,
  }) : _orgId = orgId,
       _superAdminUserId = superAdminUserId;

  @override
  Future<void> inviteUser({
    required String email,
    required UserRole role,
    required String token,
    required String invitationId,
    required DateTime expiresAtUtc,
  }) async {
    await _client.rpc(
      'super_admin_invite_first_admin',
      params: {
        'p_org_id': _orgId,
        'p_email': email,
        'p_role': _roleToDb(role),
        'p_token': token,
        'p_invitation_id': invitationId,
        'p_expires_at': expiresAtUtc.toIso8601String(),
        'p_invited_by': _superAdminUserId,
      },
    );
  }

  @override
  Future<void> acceptInvitation({
    required String token,
    required String userId,
  }) {
    throw UnsupportedError(
      'SuperAdminInvitationCommandService does not support acceptInvitation.',
    );
  }

  @override
  Future<void> revokeInvitation({required String invitationId}) {
    throw UnsupportedError(
      'SuperAdminInvitationCommandService does not support revokeInvitation.',
    );
  }

  String _roleToDb(UserRole role) {
    switch (role) {
      case UserRole.admin:
        return 'TENANT_ADMIN';
      case UserRole.operator:
        return 'OPERATOR';
      case UserRole.auditor:
        return 'AUDITOR';
      case UserRole.contractorViewer:
        throw ArgumentError(
          'CONTRACTOR_VIEWER invitations require dual-key setup — use tenant invitation flow',
        );
      case UserRole.superAdmin:
        throw ArgumentError('superAdmin cannot be assigned via invitation');
    }
  }
}
