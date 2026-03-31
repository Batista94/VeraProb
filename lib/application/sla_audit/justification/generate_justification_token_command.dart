import '../../../domain/enums/user_role.dart';

/// Command to generate a time-limited tokenized link for driver self-service.
///
/// [expiresInHours] must be in range [1, 72] (PO-6).
class GenerateJustificationTokenCommand {
  final String organizationId;
  final String contractId;
  final String setId;
  final UserRole callerRole;
  final String callerUserId;
  final int expiresInHours;

  const GenerateJustificationTokenCommand({
    required this.organizationId,
    required this.contractId,
    required this.setId,
    required this.callerRole,
    required this.callerUserId,
    required this.expiresInHours,
  });
}
