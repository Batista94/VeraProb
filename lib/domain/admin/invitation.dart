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
  });

  bool get isExpired => DateTime.now().toUtc().isAfter(expiresAtUtc);
  bool get isAccepted => acceptedAtUtc != null;
  bool get isRevoked => revokedAtUtc != null;
  bool get isActive => !isExpired && !isAccepted && !isRevoked;

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
  ];
}
