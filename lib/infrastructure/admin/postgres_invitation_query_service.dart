import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/domain/admin/invitation.dart';
import 'package:veraprob/domain/admin/invitation_repository.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/core/utils/date_time_provider.dart';

/// PostgreSQL read-side implementation of [InvitationRepository].
/// Uses direct table queries â€” RLS scopes reads to the caller's org.
class PostgresInvitationQueryService implements InvitationRepository {
  final SupabaseClient _client;
  final IDateTimeProvider _dateTimeProvider;

  PostgresInvitationQueryService(this._client, this._dateTimeProvider);

  @override
  Future<List<Invitation>> listByOrganization(String organizationId) async {
    final rows = await _client
        .from('invitations')
        .select()
        .eq('organization_id', organizationId)
        .order('created_at_utc', ascending: false);

    return (rows as List)
        .map((r) => _fromRow(r as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<Invitation?> findActiveByToken(String token) async {
    final row = await _client
        .from('invitations')
        .select()
        .eq('token', token)
        .isFilter('accepted_at_utc', null)
        .isFilter('revoked_at_utc', null)
        .gt('expires_at_utc', _dateTimeProvider.nowUtc().toIso8601String())
        .maybeSingle();

    if (row == null) return null;
    return _fromRow(row);
  }

  Invitation _fromRow(Map<String, dynamic> row) {
    return Invitation(
      id: row['id'] as String,
      organizationId: row['organization_id'] as String,
      email: row['email'] as String,
      role: _parseRole(row['role'] as String),
      token: row['token'] as String,
      invitedBy: row['invited_by'] as String,
      createdAtUtc: DateTime.parse(row['created_at_utc'] as String).toUtc(),
      expiresAtUtc: DateTime.parse(row['expires_at_utc'] as String).toUtc(),
      acceptedAtUtc: row['accepted_at_utc'] != null
          ? DateTime.parse(row['accepted_at_utc'] as String).toUtc()
          : null,
      revokedAtUtc: row['revoked_at_utc'] != null
          ? DateTime.parse(row['revoked_at_utc'] as String).toUtc()
          : null,
    );
  }

  UserRole _parseRole(String dbRole) {
    switch (dbRole) {
      case 'TENANT_ADMIN':
        return UserRole.admin;
      case 'OPERATOR':
        return UserRole.operator;
      case 'AUDITOR':
        return UserRole.auditor;
      case 'CONTRACTOR_VIEWER':
        return UserRole.contractorViewer;
      default:
        throw ArgumentError('Unknown DB role: $dbRole');
    }
  }
}
