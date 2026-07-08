import 'package:equatable/equatable.dart';
import 'package:veraprob/domain/enums/user_role.dart';

/// Represents a pending or past invitation to join an organization.
class Invitation extends Equatable {
  final String id;
  final String organizationId;
  final String email;
  final UserRole role;
  final String token;
  final String invitedBy;
  final DateTime createdAtUtc;
  final DateTime expiresAtUtc;
  final DateTime? acceptedAtUtc;
  final DateTime? revokedAtUtc;
  final String? tenantRoleId;

  const Invitation({
    required this.id,
    required this.organizationId,
    required this.email,
    required this.role,
    required this.token,
    required this.invitedBy,
    required this.createdAtUtc,
    required this.expiresAtUtc,
    this.acceptedAtUtc,
    this.revokedAtUtc,
    this.tenantRoleId,
  });

  bool isExpiredAt(DateTime nowUtc) => nowUtc.isAfter(expiresAtUtc);

  bool get isAccepted => acceptedAtUtc != null;
  bool get isRevoked => revokedAtUtc != null;
  bool isActiveAt(DateTime nowUtc) =>
      !isExpiredAt(nowUtc) && !isAccepted && !isRevoked;

  @override
  List<Object?> get props => [
    id,
    organizationId,
    email,
    role,
    token,
    invitedBy,
    createdAtUtc,
    expiresAtUtc,
    acceptedAtUtc,
    revokedAtUtc,
    tenantRoleId,
  ];
}
