import 'package:veraprob/application/shared/app_types.dart';

/// Read model for [Invitation] used in presentation layer.
///
/// Pilar INV-18: Domain sovereignty enforced via application DTO.
class InvitationView {
  final String id;
  final String organizationId;
  final String email;
  final UserRole role; // Changed from String to UserRole
  final String token;
  final String invitedBy;
  final DateTime createdAtUtc;
  final DateTime expiresAtUtc;
  final bool isActive;
  final bool isExpired;
  final bool isAccepted;

  const InvitationView({
    required this.id,
    required this.organizationId,
    required this.email,
    required this.role,
    required this.token,
    required this.invitedBy,
    required this.createdAtUtc,
    required this.expiresAtUtc,
    this.isActive = false,
    this.isExpired = false,
    this.isAccepted = false,
  });

  factory InvitationView.fromDomain(Invitation invitation) {
    return InvitationView(
      id: invitation.id,
      organizationId: invitation.organizationId,
      email: invitation.email,
      role: invitation.role, // Pure domain enum
      token: invitation.token,
      invitedBy: invitation.invitedBy,
      createdAtUtc: invitation.createdAtUtc,
      expiresAtUtc: invitation.expiresAtUtc,
      isActive: invitation.isActive,
      isExpired: invitation.isExpired,
      isAccepted: invitation.isAccepted,
    );
  }
}
