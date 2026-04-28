import 'package:equatable/equatable.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';

/// Represents a SuperAdmin impersonation session.
///
/// Security model:
/// - Max 1 active session per impersonator (DB trigger enforced)
/// - Sessions expire after [expiresAt] (typically 30 minutes)
/// - Revocation sets [revokedAt] — JWT may still be valid until exp,
///   but Edge Functions check [revokedAt] before processing
///
/// INV-1:  [targetOrgId] becomes the JWT organization_id during impersonation.
/// INV-22: Impersonator with target_org=A cannot access org B data.
/// INV-26: Impersonation of non-existent/deleted org → 404.
class ImpersonationSession extends Equatable {
  final String id;
  final String impersonatorUserId;
  final String targetOrgId;
  final String? targetUserId;
  final DateTime issuedAt;
  final DateTime expiresAt;
  final DateTime? revokedAt;
  final String? revocationReason;
  final String ticketId;

  ImpersonationSession({
    required this.id,
    required this.impersonatorUserId,
    required this.targetOrgId,
    this.targetUserId,
    required this.issuedAt,
    required this.expiresAt,
    this.revokedAt,
    this.revocationReason,
    required this.ticketId,
  }) {
    if (ticketId.trim().isEmpty) {
      throw const IntegrityException(
        'ticket_id is required for impersonation sessions',
        field: 'ticketId',
      );
    }
  }

  /// Whether this session is currently active (not revoked and not expired).
  bool isActiveAt(DateTime now) => revokedAt == null && expiresAt.isAfter(now);

  /// Remaining duration until expiration.
  Duration remainingAt(DateTime now) {
    if (!isActiveAt(now)) return Duration.zero;
    return expiresAt.difference(now);
  }

  factory ImpersonationSession.fromJson(Map<String, dynamic> json) {
    return ImpersonationSession(
      id: json['id'] as String,
      impersonatorUserId: json['impersonator_user_id'] as String,
      targetOrgId: json['target_org_id'] as String,
      targetUserId: json['target_user_id'] as String?,
      issuedAt: DateTime.parse(json['issued_at'] as String).toUtc(),
      expiresAt: DateTime.parse(json['expires_at'] as String).toUtc(),
      revokedAt: json['revoked_at'] != null
          ? DateTime.parse(json['revoked_at'] as String).toUtc()
          : null,
      revocationReason: json['revocation_reason'] as String?,
      ticketId: json['ticket_id'] as String,
    );
  }

  @override
  List<Object?> get props => [
    id,
    impersonatorUserId,
    targetOrgId,
    targetUserId,
    issuedAt,
    expiresAt,
    revokedAt,
    revocationReason,
    ticketId,
  ];
}
