import 'package:flutter/foundation.dart';
import 'package:veraprob/application/shared/app_types.dart';

/// DTO for organization member information.
/// 
/// Pilar INV-18: Domain sovereignty enforced via immutable DTO.
@immutable
class OrgMember {
  final String userId;
  final String email;
  final UserRole role;
  final DateTime invitedAt;
  final DateTime? lastSignIn;

  const OrgMember({
    required this.userId,
    required this.email,
    required this.role,
    required this.invitedAt,
    this.lastSignIn,
  });
}

/// Query service for organization member management.
/// 
/// Decoupled from infrastructure implementations.
abstract class UserManagementQueryService {
  Future<List<OrgMember>> getMembers();
}
